part of '../main.dart';

enum _DriverRidesHubSegment { available, myRides, history }

/// Cross-instance cache of the last known good driver photo URL keyed by
/// driverId. Survives State recreation across navigation, theme change, and
/// short windows where [activeDriverSessionNotifier] is null while standalone
/// restore is in progress. Never mixes photos across different driverIds.
final Map<String, String> _lastKnownDriverPhotoByDriverId = <String, String>{};

void _rememberLastKnownDriverPhoto(String? driverId, String? photoUrl) {
  final id = (driverId ?? '').trim();
  final url = (photoUrl ?? '').trim();
  if (id.isEmpty || url.isEmpty) return;
  _lastKnownDriverPhotoByDriverId[id] = url;
}

String? _readLastKnownDriverPhoto(String? driverId) {
  final id = (driverId ?? '').trim();
  if (id.isEmpty) return null;
  final cached = _lastKnownDriverPhotoByDriverId[id];
  if (cached == null) return null;
  return cached.trim().isEmpty ? null : cached;
}

class _DriverHomePageState extends State<DriverHomePage>
    with TickerProviderStateMixin {
  ValueListenable<DriverThemeVariant> get _activeDriverThemeListenable =>
      widget.openedFromBusinessHome
      ? companyDriverViewThemeNotifier
      : driverAppThemeNotifier;

  // Instance-level redirect so existing file-local theme reads stay context-aware.
  ValueListenable<DriverThemeVariant> get driverThemeNotifier =>
      _activeDriverThemeListenable;

  String? _lastPaymentConfirmationSnackbarId;
  DateTime? _trackingStartedAt; // tracking start timestamp
  bool _isStartingTrip = false; // UX: start button state
  Timer? _meterTicker;
  DateTime? _lastMeterDebugAt;

  // Manual (GPS-style) mode when no booking is active
  final TextEditingController _manualFromCtrl = TextEditingController();
  final TextEditingController _manualToCtrl = TextEditingController();
  // --- Manual A→B autocomplete (Mapbox Geocoding) ---
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();
  Timer? _fromDebounce;
  Timer? _toDebounce;
  List<_PlaceSuggestion> _fromSuggestions = <_PlaceSuggestion>[];
  List<_PlaceSuggestion> _toSuggestions = <_PlaceSuggestion>[];
  mb.Point? _manualFromPoint;
  mb.Point? _manualToPoint;

  // Ride mode (driving vs waiting)
  bool _isWaiting = false;
  bool _driverManualPause = false;
  bool _driverAvailabilitySaving = false;
  String _resolvedOperationalAvailability = 'available';
  Timer? _driverAvailabilityPollTimer;
  bool _driverAvailabilityRefreshInFlight = false;
  DateTime? _lastDriverAvailabilityRefreshAt;
  static const Duration _driverAvailabilityPollInterval = Duration(seconds: 20);
  static const Duration _driverAvailabilityMinRefreshInterval = Duration(
    seconds: 15,
  );
  VoidCallback? _driversNotifierListener;
  VoidCallback? _activeDriverSessionListener;
  DateTime? _waitStartedAt;
  Duration _waitElapsed = Duration.zero;

  // Pricing (UI-only fallback; worker remains source of truth)
  static const double _fallbackStartFee = 3.0;
  static const double _fallbackPerKm =
      1.50; // placeholder until worker streams live rates
  static const double _fallbackWaitPerMin =
      40.0 / 60.0; // €40/h = €0.666.../min

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<BookingItem> _bookings = [];
  bool _loadingBookings = true;
  String? _bookingsError;
  int? _completedTodayCount;
  bool _completedTodayLoading = false;
  final Set<String> _bookingActionInFlight = <String>{};
  final Map<String, String> _bookingStatusOverrides = <String, String>{};
  final Set<String> _deletedBookingIds = <String>{};
  final ValueNotifier<int> _bookingsUiVersion = ValueNotifier<int>(0);

  Timer? _bookingPollTimer; // auto-refresh bookings
  Future<void>? _bookingsRefreshInFlight;
  DateTime? _lastBookingsRefreshAt;
  DateTime? _lastStatusTriggeredRefreshAt;
  DateTime? _lastManualRefreshAt;
  // F3-D: monotonically increasing sequence used to discard stale driver
  // bookings refresh responses (defense-in-depth on top of the in-flight
  // guard) and to scope PRESERVE_AVAILABLE_ON_EMPTY decisions.
  int _driverBookingsRefreshSeq = 0;
  // G3-L: when a forced refresh arrives while another refresh is in flight,
  // queue exactly one follow-up trigger and run it after the current refresh
  // completes. Without this, the business-preview entry path was racing
  // init_boot vs business_preview_restore: init_boot started before the
  // business preview driver/session had been hydrated, business_preview_restore
  // was dropped as "in_flight", and the user only saw the assigned ride after
  // the next periodic poll fired. We deliberately keep just one slot so we
  // do not create duplicate timers or unbounded queues.
  String? _pendingFollowUpRefreshTrigger;
  // G3-L: cooldown so My-rides chip-tap force refreshes from business preview
  // do not cascade into spam; rides reflect server-side dispatch within
  // seconds of the chip tap, but we should not re-fire on every rebuild.
  DateTime? _lastBusinessPreviewMyRidesRefreshAt;
  static const Duration _businessPreviewMyRidesRefreshCooldown = Duration(
    seconds: 6,
  );
  bool _bookingsHubVisible = false;
  _DriverRidesHubSegment _ridesHubSegment = _DriverRidesHubSegment.available;
  int? _activeBookingPollIntervalMs;
  static const Duration _bookingsPollIntervalFastList = Duration(seconds: 9);
  static const Duration _bookingsPollIntervalSafeLive = Duration(seconds: 25);
  static const Duration _bookingsMinRefreshIntervalFastList = Duration(
    seconds: 8,
  );
  static const Duration _bookingsMinRefreshIntervalSafeLive = Duration(
    seconds: 20,
  );
  static const Duration _manualRefreshCooldown = Duration(seconds: 4);
  static const Duration _statusRefreshCooldown = Duration(seconds: 8);
  int _activeBookingRefreshTimerCount = 0;
  String? _businessPreviewDriverId;

  // Boot splash (logo on dark background + loader)
  bool _bootSplashVisible = true;

  bool _showBootSplash = true; // alias for older/other UI refs
  bool _bootMinElapsed = false;
  bool _bootFirstLoadDone = false;
  DateTime? _bootStartedAt;

  // Active trip state
  String? _activeTripId;
  String? _activeDirectTripId;
  BookingItem? _activeBooking;
  bool _directRideActive = false;
  bool _directTripStartWorkerOk = false;
  bool _directTripStopWorkerOk = false;
  String? _directRideDestinationText;
  _LonLat? _directRideDestinationPoint;
  double? _directRideEstimatedFare;
  bool _directRideEstimateLoading = false;
  String? _directRideEstimateError;
  String _directRideEstimateCurrency = kDefaultCurrency;
  Timer? _directRideEstimateDebounce;
  Timer? _directRideEstimateLocationRetryTimer;
  int _directRideEstimateRequestSeq = 0;
  String? _directRideEstimateSignature;
  int _directRideLocationRetryCount = 0;
  String? _directRideLocationRetryDestination;
  static const int _maxDirectRideLocationRetries = 1;

  // Location tracking
  StreamSubscription<geo.Position>? _posSub;
  int _activeGeolocatorSubscriptionCount = 0;
  geo.Position? _lastPos;
  geo.Position? _startPos;
  double _kmDriven = 0.0;

  // Ping status
  String _lastPing = '—';
  int _pingCount = 0;

  // Map controller
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _driverPointManager;
  mb.PointAnnotationManager? _pinsPointManager;
  mb.PolylineAnnotationManager? _routeLineManager;
  String _activeMapStyleUri = '';

  mb.PointAnnotation? _driverMarker;
  mb.PointAnnotation? _pickupPin;
  mb.PointAnnotation? _dropoffPin;
  mb.PolylineAnnotation? _routeLineOutline;
  mb.PolylineAnnotation? _routeLine;
  // NAV-OS-R2: muted grey polyline for the already-driven route section.
  mb.PolylineAnnotation? _routeLineCompleted;
  String _driverMarkerIcon = 'triangle-15';
  Uint8List? _driverTaxiMarkerBytes;
  bool _driverTaxiMarkerLoadAttempted = false;
  bool _driverTaxiMarkerAvailable = false;
  bool _driverMarkerUsesTaxiAsset = false;
  // NAV-R12-D: marker self-heal + update-coalescing state (pure decisions
  // live in NavMarkerLifecycle; the widget only wires timers and Mapbox).
  final NavMarkerLifecycle _markerLifecycle = NavMarkerLifecycle();
  Timer? _markerSelfHealTimer;
  geo.Position? _pendingMarkerUpdatePos;
  int _consecutiveMarkerUpdateFailures = 0;
  DateTime? _lastMarkerAuxSyncAt;
  String? _lastNavR12MarkerSignature;
  // NAV-R12-E1: last-wins pending camera target while an animation is in
  // flight or the follow throttle is active (fresh target decision comes
  // from NavCameraTargetPolicy).
  geo.Position? _pendingFollowCameraPos;
  Timer? _pendingFollowCameraTimer;
  String? _lastNavR12CameraSignature;
  // NAV-R12-E2: cheap route version so banner diagnostics can show which
  // route generation an instruction belongs to; bumped on every applied
  // route/reroute step list.
  int _routeStepsVersion = 0;
  String? _lastNavR12BannerSignature;
  bool _mapboxLocationPuckRestoreEnabled = false;
  bool _mapboxLocationPuckSuppressedForNav = false;
  bool? _lastSyncedMapboxPuckHidden;
  late final Widget _stableMapWidget;
  String? _pendingMapStyleUri;
  bool _mapStyleChanging = false;
  // NAV-UI-R6D: compact expandable "more" chip for portrait nav quick actions.
  bool _navQuickActionsMoreExpanded = false;
  // NAV-UI-R6E: taxi visual captured just before setStyleURI so the marker can
  // be recreated immediately after style load without waiting for GPS.
  ({double lat, double lon, double bearing, String source})?
  _taxiVisualSnapshotForStyleSwap;
  // NAV-OS-R2: last forward-bearing guard state for diagnostics.
  bool _lastR2ReversedGuard = false;
  double? _lastR2BearingDeltaDeg;
  DateTime? _lastMapWidgetBuildLogAt;
  DateTime? _lastDriverBuildLogAt;

  // Splash animations (premium boot feel)
  late final AnimationController _splashAnimCtrl;
  late final Animation<double> _splashPulse;

  // Active HUD pulse (only meaningful when tracking)
  late final AnimationController _activePulseCtrl;
  late final Animation<double> _activePulse;
  // UI/Camera
  bool _followCar = false;
  _CameraMode _cameraMode = _CameraMode.overview;
  MapThemeMode? _mapThemeOverride;
  DriverMapVisualMode _driverMapVisualMode = DriverMapVisualMode.street;
  double _lastMapCameraZoom = kDriverMapInitialZoom;
  bool _navigationWakelockEnabled = false;
  bool _hasSwitchedToFollow = false;
  double _lastKnownBearing = 0.0;
  bool _allowOverviewCamera = false;
  DateTime? _lastFollowCameraAt;
  bool _followCameraInFlight = false;
  bool _gpsQualityWeak = false;
  double? _lastSmoothedCameraBearing;
  static const double _followCameraStaleGpsMaxAgeSec = 12.0;
  static const double _followCameraPoorAccuracyM = 65.0;

  // Route stats
  List<_LonLat> _routeCoords = [];
  double? _routeKm;
  int? _routeDurationSec;
  String _lastPinsDrawSignature = '';
  DateTime? _lastPinsDrawAt;
  String _lastRouteDrawSignature = '';
  DateTime? _lastRouteDrawAt;
  static const Duration _routeDrawDebounce = Duration(seconds: 2);
  _RideRoutePhase _routePhase = _RideRoutePhase.trip;
  List<_NavStep> _routeSteps = const <_NavStep>[];
  int _nextStepIndex = 0;
  String? _nextNavInstruction;
  String? _nextNavStreet;
  double? _nextNavDistanceM;
  String? _nextNavType;
  String? _nextNavModifier;
  NavInstructionSnapshot? _navInstructionSnapshot;
  bool _navStepsLoading = false;
  double _uiArrowBearing = 0.0;
  _RouteSnap? _lastRouteSnap;
  double? _lastMovementBearing;
  bool _useMatchedVisual = false;
  int _matchEnterHits = 0;
  int _matchExitHits = 0;
  double? _lastVisualProgressM;
  bool _routeLineProgressTrimmed = false;
  double _lastRouteLineTrimProgressM = 0.0;
  DateTime? _lastRouteLineTrimAt;
  double _lastMarkerLagM = 0.0;
  final Map<String, Future<_RoutePreviewData?>> _nextRidePreviewCache =
      <String, Future<_RoutePreviewData?>>{};
  final Map<String, DateTime> _lastNavDebugAt = <String, DateTime>{};
  final DriverNavEngine _driverNavEngine = DriverNavEngine();
  NavEngineOutput? _lastNavEngineOutput;
  String? _lastNavEngineRefreshKey;
  // NAV-R3: smooth visual interpolation between engine target updates.
  bool _navR3MotionActive = false;
  double? _navR3VisualLat;
  double? _navR3VisualLon;
  double _navR3VisualBearing = 0.0;
  double _navR3FromLat = 0.0;
  double _navR3FromLon = 0.0;
  double _navR3ToLat = 0.0;
  double _navR3ToLon = 0.0;
  double _navR3FromBearing = 0.0;
  double _navR3ToBearing = 0.0;
  DateTime? _navR3AnimStartedAt;
  Duration _navR3AnimDuration = const Duration(milliseconds: 1000);
  Timer? _navR3MotionTimer;
  final DriverNavRouteProgress _driverNavRouteProgress =
      DriverNavRouteProgress();
  NavRouteProgressOutput? _lastNavRouteProgress;
  int? _navRouteProgressRouteFingerprint;
  final DriverNavCameraPolicy _driverNavCameraPolicy = DriverNavCameraPolicy();
  NavCameraPolicyOutput? _lastNavCameraPolicy;
  final DriverNavConfidenceEngine _driverNavConfidenceEngine =
      DriverNavConfidenceEngine();
  NavConfidenceOutput? _lastNavConfidence;
  // NAV-R14: local complexity caution (offline, no cloud).
  final NavComplexityMonitor _navComplexityMonitor = NavComplexityMonitor();
  NavCautionState _lastNavCautionState = NavCautionState.inactive;
  String? _lastNavR14ComplexitySignature;
  final DriverNavMotionPrediction _driverNavMotionPrediction =
      DriverNavMotionPrediction();
  NavMotionPredictionOutput? _lastNavMotionPrediction;
  final DriverNavInstructionPolicy _driverNavInstructionPolicy =
      DriverNavInstructionPolicy();
  final DriverNavValidationEngine _driverNavValidationEngine =
      DriverNavValidationEngine();
  DateTime? _lastNavValidationSampleAt;
  bool _navValidationPendingCameraFollowed = false;
  String? _navValidationPendingCameraSkipReason;
  DateTime? _lastNavDiagGpsAt;
  DateTime? _lastNavDiagMarkerAt;
  NavR9OfflineUiState? _lastNavDiagR9State;
  DateTime? _lastNavDiagR9EnteredAt;
  bool _offRouteLikely = false;
  int _offRouteHitCount = 0;
  String? _lastNavR12OffRouteSignature;
  // NAV-R12-B: why the route-adaptation state is active — 'none'
  // | 'opposite_direction' | 'opposite_direction_strong'
  // | 'backward_progress' | 'snap_distance'.
  String _offRouteReason = 'none';
  bool _isRerouting = false;
  DateTime? _lastRerouteAt;
  bool _lastRerouteFailed = false;
  String? _rerouteReason;
  DateTime? _offRouteRerouteDebounceStartedAt;
  static const Duration _rerouteCooldown = Duration(seconds: 25);
  // NAV-R12-B: route-deviation off-route must correct fast, and a failed
  // reroute retries on a short backoff instead of the full cooldown.
  static const Duration _rerouteCooldownRouteDeviation = Duration(seconds: 8);
  static const Duration _rerouteFailedRetryBackoff = Duration(seconds: 3);
  int _routeCleanupEpoch = 0;
  NavigationWorkerOfflineCorridorMetadata? _lastOfflineCorridorMetadata;
  bool _offlineCorridorMetadataLoading = false;
  bool _offlineCorridorMetadataError = false;
  String? _offlineCorridorMetadataFingerprint;
  DateTime? _offlineCorridorMetadataFetchedAt;
  int _offlineCorridorMetadataRequestId = 0;
  int _mapRedrawCountThisMinute = 0;
  int _routeRedrawCountThisMinute = 0;
  Timer? _renderDebugWindowTimer;

  void _resetNavProgressState({bool clearRoute = false}) {
    if (clearRoute) {
      _routeCoords = [];
      _routeKm = null;
      _routeDurationSec = null;
    }
    _routeSteps = const <_NavStep>[];
    _nextStepIndex = 0;
    _nextNavInstruction = null;
    _nextNavStreet = null;
    _nextNavDistanceM = null;
    _nextNavType = null;
    _nextNavModifier = null;
    _navInstructionSnapshot = null;
    _lastRouteSnap = null;
    _lastMovementBearing = null;
    _useMatchedVisual = false;
    _matchEnterHits = 0;
    _matchExitHits = 0;
    _lastVisualProgressM = null;
    _routeLineProgressTrimmed = false;
    _lastRouteLineTrimProgressM = 0.0;
    _lastRouteLineTrimAt = null;
    _lastMarkerLagM = 0.0;
    _offRouteHitCount = 0;
    _offRouteLikely = false;
    _offRouteReason = 'none';
    _isRerouting = false;
    _lastRerouteFailed = false;
    _rerouteReason = null;
    _offRouteRerouteDebounceStartedAt = null;
    _driverNavEngine.reset();
    _lastNavEngineOutput = null;
    _lastNavEngineRefreshKey = null;
    _resetNavR3MotionState();
    _resetNavRouteProgressState();
    _resetNavCameraPolicyState();
    _resetNavConfidenceState();
    _resetNavComplexityState();
    _resetNavMotionPredictionState();
    _resetNavInstructionPolicyState();
    if (clearRoute) {
      _resetOfflineCorridorMetadataState();
      _resetNavValidationState();
    }
  }

  void _resetNavValidationState({bool flushReport = false}) {
    if (flushReport) {
      _flushNavValidationReport(reason: 'tracking_stop');
      return;
    }
    _driverNavValidationEngine.reset();
    _lastNavValidationSampleAt = null;
    _navValidationPendingCameraFollowed = false;
    _navValidationPendingCameraSkipReason = null;
  }

  void _flushNavValidationReport({required String reason}) {
    final report = _driverNavValidationEngine.buildReport();
    if (report.sampleCount > 0) {
      debugPrint(
        '[NAV_R10_REPORT] durationSec=${report.durationSec} '
        'samples=${report.sampleCount} '
        'score=${report.overallDriverOsScore.toStringAsFixed(1)} '
        'gps=${report.avgGpsScore.toStringAsFixed(1)} '
        'route=${report.avgRouteConfidence.toStringAsFixed(1)} '
        'confidence=${report.avgOverallConfidence.toStringAsFixed(1)} '
        'snapAvg=${report.avgSnapDistanceM.toStringAsFixed(1)} '
        'predictionEvents=${report.predictionEvents} '
        'offRouteEvents=${report.offRouteEvents} '
        'cameraSkips=${report.cameraSkipEvents} '
        'label=${report.summaryLabel.logLabel} '
        'reason=$reason',
      );
      unawaited(
        NavDiagnosticsRecorder.instance.recordValidationReport(
          durationSec: report.durationSec,
          sampleCount: report.sampleCount,
          overallScore: report.overallDriverOsScore,
          gpsScore: report.avgGpsScore,
          routeConfidence: report.avgRouteConfidence,
          overallConfidence: report.avgOverallConfidence,
          snapAvgM: report.avgSnapDistanceM,
          predictionEvents: report.predictionEvents,
          offRouteEvents: report.offRouteEvents,
          cameraSkips: report.cameraSkipEvents,
          label: report.summaryLabel.logLabel,
          reason: reason,
        ),
      );
    }
    unawaited(
      NavDiagnosticsRecorder.instance.endSessionIfActive(reason: reason),
    );
    _driverNavValidationEngine.reset();
    _lastNavValidationSampleAt = null;
    _navValidationPendingCameraFollowed = false;
    _navValidationPendingCameraSkipReason = null;
  }

  void _maybeAddNavValidationSample(geo.Position pos) {
    if (!_isActiveDriverNavEngineContext()) return;

    final now = DateTime.now();
    final lastSampleAt = _lastNavValidationSampleAt;
    if (lastSampleAt != null &&
        now.difference(lastSampleAt).inMilliseconds < 1000) {
      return;
    }
    _lastNavValidationSampleAt = now;

    final progress = _lastNavRouteProgress;
    final confidence = _lastNavConfidence;
    final prediction = _lastNavMotionPrediction;
    final engineOutput = _lastNavEngineOutput;

    _driverNavValidationEngine.addSample(
      NavValidationSample(
        timestamp: now,
        gpsAccuracyM: pos.accuracy.isFinite && pos.accuracy > 0
            ? pos.accuracy
            : null,
        speedKmh: _speedKmhFor(pos),
        routeConfidence: progress?.confidence,
        snapDistanceM: progress?.snapDistanceM,
        overallConfidence: confidence?.overallScore,
        cameraScore: confidence?.cameraScore,
        instructionScore: confidence?.instructionScore,
        predictionActive: prediction?.predictionActive ?? false,
        offRouteLikely: progress?.offRouteLikely ?? _offRouteLikely,
        markerAnimated:
            _navR3MotionActive || (engineOutput?.shouldAnimateMarker ?? false),
        cameraFollowed: _navValidationPendingCameraFollowed,
        cameraSkippedReason: _navValidationPendingCameraSkipReason,
      ),
    );
  }

  void _resetOfflineCorridorMetadataState() {
    _offlineCorridorMetadataRequestId++;
    _lastOfflineCorridorMetadata = null;
    _offlineCorridorMetadataLoading = false;
    _offlineCorridorMetadataError = false;
    _offlineCorridorMetadataFingerprint = null;
    _offlineCorridorMetadataFetchedAt = null;
  }

  String _routeGeometryFingerprint() {
    if (_routeCoords.length < 2) return '';
    final first = _routeCoords.first;
    final last = _routeCoords.last;
    return '${_routeCoords.length}|'
        '${first.lat.toStringAsFixed(3)}|${first.lon.toStringAsFixed(3)}|'
        '${last.lat.toStringAsFixed(3)}|${last.lon.toStringAsFixed(3)}|'
        '${(_routeKm ?? 0).toStringAsFixed(1)}';
  }

  Map<String, dynamic> _routeGeometryGeoJson() {
    return <String, dynamic>{
      'type': 'LineString',
      'coordinates': _routeCoords
          .map((coord) => <double>[coord.lon, coord.lat])
          .toList(growable: false),
    };
  }

  bool _hasOfflineCorridorNavContext() {
    return _cameraMode == _CameraMode.follow || _liveRideActive;
  }

  void _logCloudNav3({required String result, required String reason}) {
    _logNavBounded(
      'CLOUD_NAV_3',
      'endpoint=offline result=$result reason=$reason',
      intervalMs: 2500,
    );
  }

  String _formatCorridorByteRange(int minBytes, int maxBytes) {
    String one(int bytes) {
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(0)} KB';
      }
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${one(minBytes)} - ${one(maxBytes)}';
  }

  Future<void> _maybeFetchOfflineCorridorMetadata({bool force = false}) async {
    if (!kUseNavigationWorker) {
      _logCloudNav3(result: 'disabled', reason: 'flag_off');
      return;
    }
    if (_routeCoords.length < 2) {
      _logCloudNav3(result: 'skipped', reason: 'no_route_geometry');
      return;
    }
    if (!_hasOfflineCorridorNavContext() && !force) {
      _logCloudNav3(result: 'skipped', reason: 'no_nav_context');
      return;
    }

    final fingerprint = _routeGeometryFingerprint();
    if (!force &&
        fingerprint == _offlineCorridorMetadataFingerprint &&
        _lastOfflineCorridorMetadata != null) {
      _logCloudNav3(result: 'ready', reason: 'cached');
      return;
    }
    if (_offlineCorridorMetadataLoading &&
        fingerprint == _offlineCorridorMetadataFingerprint) {
      return;
    }

    if (fingerprint != _offlineCorridorMetadataFingerprint) {
      _lastOfflineCorridorMetadata = null;
      _offlineCorridorMetadataError = false;
      _offlineCorridorMetadataFetchedAt = null;
    }

    final requestId = ++_offlineCorridorMetadataRequestId;
    if (mounted) {
      setState(() {
        _offlineCorridorMetadataLoading = true;
        _offlineCorridorMetadataError = false;
      });
    } else {
      _offlineCorridorMetadataLoading = true;
      _offlineCorridorMetadataError = false;
    }
    _logCloudNav3(result: 'loading', reason: 'fetch_start');

    try {
      final client = DriverNavigationWorkerClient(
        baseUrl: kNavigationWorkerBaseUrl,
      );
      final metadata = await client.offlineCorridorMetadata(
        geometry: _routeGeometryGeoJson(),
        country: _navigationWorkerCountryCode(),
        routeId: _activeTripId?.trim(),
      );
      if (requestId != _offlineCorridorMetadataRequestId) return;
      if (fingerprint != _routeGeometryFingerprint()) {
        _logCloudNav3(result: 'skipped', reason: 'stale_geometry');
        return;
      }
      if (metadata == null) {
        if (mounted) {
          setState(() {
            _offlineCorridorMetadataLoading = false;
            _offlineCorridorMetadataError = true;
          });
        } else {
          _offlineCorridorMetadataLoading = false;
          _offlineCorridorMetadataError = true;
        }
        _logCloudNav3(result: 'error', reason: 'worker_null');
        return;
      }
      if (mounted) {
        setState(() {
          _lastOfflineCorridorMetadata = metadata;
          _offlineCorridorMetadataFingerprint = fingerprint;
          _offlineCorridorMetadataFetchedAt = DateTime.now();
          _offlineCorridorMetadataLoading = false;
          _offlineCorridorMetadataError = false;
        });
      } else {
        _lastOfflineCorridorMetadata = metadata;
        _offlineCorridorMetadataFingerprint = fingerprint;
        _offlineCorridorMetadataFetchedAt = DateTime.now();
        _offlineCorridorMetadataLoading = false;
        _offlineCorridorMetadataError = false;
      }
      _logCloudNav3(result: 'ready', reason: metadata.supportedStatus);
    } catch (_) {
      if (requestId != _offlineCorridorMetadataRequestId) return;
      if (mounted) {
        setState(() {
          _offlineCorridorMetadataLoading = false;
          _offlineCorridorMetadataError = true;
        });
      } else {
        _offlineCorridorMetadataLoading = false;
        _offlineCorridorMetadataError = true;
      }
      _logCloudNav3(result: 'error', reason: 'fetch_failed');
    }
  }

  Widget _buildNavOfflineCorridorPrepPanel({required Color navText}) {
    final style = TextStyle(
      color: navText.withOpacity(0.72),
      fontSize: 10.5,
      height: 1.25,
    );

    if (!kUseNavigationWorker) {
      return Text(
        _tr(
          nl: 'Route-corridor voorbereiding beschikbaar zodra Navigation Core actief is.',
          en: 'Route corridor preparation is available when Navigation Core is active.',
          fr: 'La preparation du corridor de route sera disponible quand Navigation Core sera actif.',
          es: 'La preparacion del corredor de ruta estara disponible cuando Navigation Core este activo.',
        ),
        textAlign: TextAlign.center,
        style: style,
      );
    }

    if (_offlineCorridorMetadataLoading) {
      return Text(
        _tr(
          nl: 'Offline route-corridor wordt berekend…',
          en: 'Preparing offline route corridor…',
          fr: 'Preparation du corridor de route hors ligne…',
          es: 'Preparando corredor de ruta sin conexion…',
        ),
        textAlign: TextAlign.center,
        style: style,
      );
    }

    if (_offlineCorridorMetadataError) {
      return Text(
        _tr(
          nl: 'Offline corridor kon niet worden voorbereid. Lokale GPS/predictie blijft actief.',
          en: 'Offline corridor could not be prepared. Local GPS/prediction remains active.',
          fr: 'Le corridor hors ligne n\'a pas pu etre prepare. GPS/prediction locale reste actif.',
          es: 'No se pudo preparar el corredor sin conexion. GPS/prediccion local sigue activo.',
        ),
        textAlign: TextAlign.center,
        style: style,
      );
    }

    final metadata = _lastOfflineCorridorMetadata;
    if (metadata != null) {
      final sizeRange = _formatCorridorByteRange(
        metadata.estimatedSizeBytesMin,
        metadata.estimatedSizeBytesMax,
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _tr(
              nl:
                  'Corridor: ${metadata.estimatedTileCountMin}-${metadata.estimatedTileCountMax} tegels · '
                  '$sizeRange · buffer ${metadata.corridorBufferMeters} m · '
                  'zoom ${metadata.zoomMin}-${metadata.zoomMax} · ${metadata.supportedStatus}',
              en:
                  'Corridor: ${metadata.estimatedTileCountMin}-${metadata.estimatedTileCountMax} tiles · '
                  '$sizeRange · buffer ${metadata.corridorBufferMeters} m · '
                  'zoom ${metadata.zoomMin}-${metadata.zoomMax} · ${metadata.supportedStatus}',
              fr:
                  'Corridor: ${metadata.estimatedTileCountMin}-${metadata.estimatedTileCountMax} tuiles · '
                  '$sizeRange · tampon ${metadata.corridorBufferMeters} m · '
                  'zoom ${metadata.zoomMin}-${metadata.zoomMax} · ${metadata.supportedStatus}',
              es:
                  'Corredor: ${metadata.estimatedTileCountMin}-${metadata.estimatedTileCountMax} teselas · '
                  '$sizeRange · buffer ${metadata.corridorBufferMeters} m · '
                  'zoom ${metadata.zoomMin}-${metadata.zoomMax} · ${metadata.supportedStatus}',
            ),
            textAlign: TextAlign.center,
            style: style,
          ),
          const SizedBox(height: 4),
          Text(
            _tr(
              nl: 'Dit is voorbereiding, geen volledige offline navigatie.',
              en: 'This is preparation, not full offline navigation.',
              fr: 'Ceci est une preparation, pas une navigation hors ligne complete.',
              es: 'Esto es preparacion, no navegacion sin conexion completa.',
            ),
            textAlign: TextAlign.center,
            style: style.copyWith(fontSize: 10, fontStyle: FontStyle.italic),
          ),
        ],
      );
    }

    return Text(
      _tr(
        nl: 'Offline route-corridor wordt berekend…',
        en: 'Preparing offline route corridor…',
        fr: 'Preparation du corridor de route hors ligne…',
        es: 'Preparando corredor de ruta sin conexion…',
      ),
      textAlign: TextAlign.center,
      style: style,
    );
  }

  bool _isRouteTaskStillValid({
    required int epoch,
    String? expectedBookingId,
    bool requireDirectRide = false,
  }) {
    if (epoch != _routeCleanupEpoch) return false;
    if (requireDirectRide && !_directRideActive) return false;
    if (expectedBookingId != null) {
      final activeId = _activeBooking?.bookingId;
      if (activeId == null || activeId != expectedBookingId) return false;
    }
    return true;
  }

  Future<void> _clearRouteAndPinAnnotationsOnly() async {
    try {
      if (_routeLineManager != null) {
        if (_routeLineOutline != null) {
          await _routeLineManager!.delete(_routeLineOutline!);
        }
        if (_routeLine != null) {
          await _routeLineManager!.delete(_routeLine!);
        }
        if (_routeLineCompleted != null) {
          await _routeLineManager!.delete(_routeLineCompleted!);
        }
      }
      _routeLineOutline = null;
      _routeLine = null;
      _routeLineCompleted = null;

      if (_pinsPointManager != null) {
        if (_pickupPin != null) {
          await _pinsPointManager!.delete(_pickupPin!);
        }
        if (_dropoffPin != null) {
          await _pinsPointManager!.delete(_dropoffPin!);
        }
      }
      _pickupPin = null;
      _dropoffPin = null;
    } catch (_) {}
  }

  Future<void> _clearActiveRouteAndNavigationState({
    required String reason,
    String? bookingId,
    bool clearActiveSelection = true,
  }) async {
    final activeBookingId = _activeBooking?.bookingId;
    final hasPolylineBefore = _routeLine != null || _routeLineOutline != null;
    final routeCoordsBefore = _routeCoords.length;
    final navStepsBefore = _routeSteps.length;
    if (!clearActiveSelection &&
        !hasPolylineBefore &&
        routeCoordsBefore == 0 &&
        navStepsBefore == 0) {
      return;
    }

    await _clearRouteAndPinAnnotationsOnly();

    if (!mounted) return;
    setState(() {
      _routeCleanupEpoch++;
      _resetNavProgressState(clearRoute: true);
      _routePhase = _RideRoutePhase.trip;
      _navStepsLoading = false;
      _cameraMode = _CameraMode.overview;
      _hasSwitchedToFollow = false;
      _followCar = false;
      _allowOverviewCamera = false;
      if (clearActiveSelection) {
        _activeTripId = null;
        _activeDirectTripId = null;
        _activeBooking = null;
        _directRideActive = false;
        _directRideDestinationText = null;
        _directRideDestinationPoint = null;
        _directRideEstimatedFare = null;
        _directRideEstimateLoading = false;
        _directRideEstimateError = null;
        _directRideEstimateCurrency = kDefaultCurrency;
        _directRideEstimateSignature = null;
        _directRideLocationRetryCount = 0;
        _directRideLocationRetryDestination = null;
        _lastPing = '—';
        _pingCount = 0;
        _kmDriven = 0.0;
        _trackingStartedAt = null;
        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;
      }
    });
    _setNavigationWakelock(false);
    await _applyMapStyleForMode();
    if (!_liveRideActive) {
      _startBookingPolling(reason: 'route_state_cleared');
    }
  }

  bool _isClosedRideStatus(String? rawStatus) {
    final s = (rawStatus ?? '').trim().toUpperCase();
    return s == 'COMPLETED' ||
        s == 'COMPLETE' ||
        s == 'CANCELLED' ||
        s == 'CANCELED' ||
        s == 'DELETED' ||
        s == 'ARCHIVED' ||
        s == 'CLOSED' ||
        s == 'DONE' ||
        s == 'FAILED' ||
        s == 'EXPIRED' ||
        s == 'DECLINED';
  }

  String _bookingActionKeyForUi(BookingItem b) {
    if (b.isOperationalLeg && b.legId.trim().isNotEmpty) {
      return b.rowKey;
    }
    return b.bookingId;
  }

  String? _effectiveStatusFor(BookingItem b) {
    return _bookingStatusOverrides[b.rowKey] ??
        _bookingStatusOverrides[b.bookingId] ??
        b.status;
  }

  Map<String, dynamic> _bookingScopeViewFor(BookingItem b) {
    return <String, dynamic>{
      ...b.details,
      'booking_id': b.bookingId,
      'bookingId': b.bookingId,
      if (b.details['booking'] is! Map)
        'booking': <String, dynamic>{...b.details},
    };
  }

  String _resolvedAssignedVehicleIdFromBookingItem(BookingItem b) {
    final booking = _bookingScopeViewFor(b);
    return (_bookingScopeFirstText(booking, const [
              ['assigned_vehicle_id'],
              ['assignedVehicleId'],
              ['vehicle_id'],
              ['vehicleId'],
              ['details', 'assigned_vehicle_id'],
              ['details', 'assignedVehicleId'],
              ['details', 'vehicle_id'],
              ['details', 'vehicleId'],
              ['booking', 'assigned_vehicle_id'],
              ['booking', 'assignedVehicleId'],
              ['booking', 'vehicle_id'],
              ['booking', 'vehicleId'],
              ['record', 'assigned_vehicle_id'],
              ['record', 'assignedVehicleId'],
              ['record', 'vehicle_id'],
              ['record', 'vehicleId'],
              ['record', 'booking', 'assigned_vehicle_id'],
              ['record', 'booking', 'assignedVehicleId'],
              ['record', 'booking', 'vehicle_id'],
              ['record', 'booking', 'vehicleId'],
            ]) ??
            '')
        .trim();
  }

  ({String actorVehicleId, String source}) _plannedTripActorVehicleContext(
    BookingItem b,
  ) {
    final assignedVehicleId = _resolvedAssignedVehicleIdFromBookingItem(b);
    if (assignedVehicleId.isNotEmpty) {
      return (actorVehicleId: assignedVehicleId, source: 'assigned_vehicle');
    }
    final sessionVehicleId =
        activeDriverSessionNotifier.value?.assignedVehicleId?.trim() ?? '';
    if (sessionVehicleId.isNotEmpty) {
      return (actorVehicleId: sessionVehicleId, source: 'session_vehicle');
    }
    final linkedVehicleIds = _activeDriverLinkedVehicleIds().toList(
      growable: false,
    )..sort();
    if (linkedVehicleIds.isNotEmpty) {
      return (actorVehicleId: linkedVehicleIds.first, source: 'linked_vehicle');
    }
    return (
      actorVehicleId: _directRideVehicleId().trim(),
      source: 'fallback_direct',
    );
  }

  bool _canOperateBookingWithGuard(
    Map<String, dynamic> booking, {
    required String action,
  }) {
    final allowed = _canActiveDriverOperateBooking(booking);
    final bookingId =
        _bookingScopeFirstText(booking, const [
          ['booking_id'],
          ['bookingId'],
          ['id'],
          ['booking', 'booking_id'],
          ['booking', 'bookingId'],
        ]) ??
        'unknown';
    final assignedVehicleId =
        _bookingScopeFirstText(booking, const [
          ['assigned_vehicle_id'],
          ['assignedVehicleId'],
          ['vehicle_id'],
          ['vehicleId'],
          ['booking', 'assigned_vehicle_id'],
          ['booking', 'assignedVehicleId'],
          ['booking', 'vehicle_id'],
          ['booking', 'vehicleId'],
        ]) ??
        '';
    final activeDriverId = _resolvedActiveDriverIdForScope();
    if (!allowed) {
      debugPrint(
        '[DRIVER_SCOPE][BLOCK] action=$action booking_id=$bookingId assigned_vehicle_id=$assignedVehicleId active_driver_id=$activeDriverId active_vehicle_id=${_activeDriverSessionVehicleIdForScope()} allowed=false',
      );
      _toast(_driverOwnershipBlockedMessage());
      return false;
    }
    return true;
  }

  List<BookingItem> _scopeFilteredOpenBookings({
    String segment = 'scope_open',
  }) {
    final enforceScope = _shouldEnforceDriverRideScopeFilter();
    return _bookings
        .where((b) => !_deletedBookingIds.contains(b.bookingId))
        .where((b) => !_isClosedRideStatus(_effectiveStatusFor(b)))
        .where((b) {
          if (!enforceScope) return true;
          if (kDriverAllowAllCompanyRidesDebug) return true;
          final booking = _bookingScopeViewFor(b);
          final decision = _driverRideScopeVisibilityDecision(
            booking,
            segment: segment,
          );
          final bookingId = b.bookingId;
          final assignedDriverId = _bookingScopeAssignedDriverId(booking) ?? '';
          final assignedVehicleId =
              _bookingScopeAssignedVehicleId(booking) ?? '';
          debugPrint(
            '[DRIVER_SCOPE][FILTER] booking_id=${_safeRefPreview(bookingId)} assigned_driver_id=${_safeRefPreview(assignedDriverId)} assigned_vehicle_id=${_safeRefPreview(assignedVehicleId)} active_driver_id=${_safeRefPreview(_resolvedActiveDriverIdForScope())} active_vehicle_id=${_safeRefPreview(_activeDriverSessionVehicleIdForScope())} segment=$segment allowed=${decision.allowed} reason=${decision.reason}',
          );
          return decision.allowed;
        })
        .toList(growable: false);
  }

  List<BookingItem> get _myAssignedVisibleBookings {
    final open = _scopeFilteredOpenBookings(segment: 'my_rides');
    if (!_shouldEnforceDriverRideScopeFilter()) {
      return _dedupeDriverVisibleBookingItems(open);
    }
    final assigned = open
        .where((b) => _bookingIsMyAssignedDriverRide(_bookingScopeViewFor(b)))
        .toList(growable: false);
    return _dedupeDriverVisibleBookingItems(assigned);
  }

  List<BookingItem> get _availableUnassignedVisibleBookings {
    if (!_shouldEnforceDriverRideScopeFilter()) return const [];
    return buildDriverAvailableUnassignedVisibleBookings(
      _scopeFilteredOpenBookings(segment: 'available'),
    );
  }

  List<BookingItem> get _historyAssignedVisibleBookings {
    final closed = _bookings
        .where((b) => !_deletedBookingIds.contains(b.bookingId))
        .where((b) => _isClosedRideStatus(_effectiveStatusFor(b)))
        .where((b) {
          if (!_shouldEnforceDriverRideScopeFilter()) return true;
          return _bookingIsMyAssignedDriverRide(_bookingScopeViewFor(b));
        })
        .toList(growable: false);
    return _dedupeDriverVisibleBookingItems(closed);
  }

  List<BookingItem> _ridesHubSegmentBookings() {
    switch (_ridesHubSegment) {
      case _DriverRidesHubSegment.available:
        return _availableUnassignedVisibleBookings;
      case _DriverRidesHubSegment.myRides:
        return _myAssignedVisibleBookings;
      case _DriverRidesHubSegment.history:
        return _historyAssignedVisibleBookings;
    }
  }

  /// Assigned/planned rides for the active driver (excludes available-unassigned pool).
  List<BookingItem> get _visibleBookings => _myAssignedVisibleBookings;

  void _markBookingsUiDirty() {
    _bookingsUiVersion.value = _bookingsUiVersion.value + 1;
  }

  bool get _mapSupported => !kIsWindows && !kIsWeb;
  bool get kIsWindows => !kIsWeb && Platform.isWindows;
  bool _isAssetRef(String v) => v.trim().toLowerCase().startsWith('assets/');

  String _maskCompanyIdForBrandLog(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '—';
    if (text.length <= 6) return '…${text.substring(text.length - 1)}';
    return '${text.substring(0, 4)}…${text.substring(text.length - 4)}';
  }

  String _activeCompanyIdForBrand() {
    for (final candidate in <String?>[
      companyProfileNotifier.value?.companyId,
      activeCompanySessionNotifier.value?.companyId,
      resolvedCompanyId,
    ]) {
      final normalized = (candidate ?? '').trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  String? _resolveDriverHomeBrandLogoRef({
    required BusinessSettingsState businessSettings,
    required ActiveDriverSession? session,
  }) {
    String? normalizeLogoRef(String? raw) {
      final text = (raw ?? '').trim();
      if (text.isEmpty) return null;
      if (_isAssetRef(text)) return text;
      final resolved = resolvePublicHttpsMediaUrl(text);
      if (resolved.isNotEmpty) return resolved;
      final lower = text.toLowerCase();
      if (lower.startsWith('https://') || lower.startsWith('http://')) {
        return text;
      }
      if (lower.startsWith('/public/media/') ||
          lower.startsWith('public-media/')) {
        return text;
      }
      if (kIsWeb) return null;
      try {
        if (File(text).existsSync()) return text;
      } catch (_) {}
      return null;
    }

    final isBusinessPreview = widget.openedFromBusinessHome;
    final brandSource = isBusinessPreview
        ? 'business_preview'
        : 'standalone_driver';
    final activeCompanyId = _activeCompanyIdForBrand();
    final sessionCompanyId = (session?.companyId ?? session?.tenantId ?? '')
        .trim();
    final previewScope = _activeBusinessPreviewScope();
    final brandCompanyId = isBusinessPreview
        ? (previewScope?.companyId ?? activeCompanyId)
        : sessionCompanyId;
    final businessLocalLogo = normalizeLogoRef(businessSettings.logoAssetPath);
    final sessionLogo = normalizeLogoRef(session?.companyLogoUrl);
    final backendLogo = normalizeLogoRef(
      localBackendBusinessProfileNotifier.value?.publicLogoUrl,
    );

    String logoSource = 'default';
    String? selected;

    if (isBusinessPreview) {
      if (businessLocalLogo != null &&
          brandCompanyId.isNotEmpty &&
          activeCompanyId == brandCompanyId) {
        selected = businessLocalLogo;
        logoSource = 'business_profile';
      } else if (sessionLogo != null) {
        selected = sessionLogo;
        logoSource = 'session';
      } else if (backendLogo != null &&
          brandCompanyId.isNotEmpty &&
          activeCompanyId == brandCompanyId) {
        selected = backendLogo;
        logoSource = 'business_profile';
      }
    } else {
      if (sessionLogo != null) {
        selected = sessionLogo;
        logoSource = 'session';
      } else if (businessLocalLogo != null &&
          sessionCompanyId.isNotEmpty &&
          activeCompanyId == sessionCompanyId) {
        selected = businessLocalLogo;
        logoSource = 'business_profile';
      } else if (backendLogo != null &&
          sessionCompanyId.isNotEmpty &&
          activeCompanyId == sessionCompanyId) {
        selected = backendLogo;
        logoSource = 'business_profile';
      } else if (businessLocalLogo != null &&
          sessionCompanyId.isNotEmpty &&
          activeCompanyId.isNotEmpty &&
          activeCompanyId != sessionCompanyId) {
        logoSource = 'blocked_mismatch';
      }
    }

    final resolvedRef = (selected ?? kFluxidiLogoAsset).trim();
    final logoPresent =
        logoSource != 'default' &&
        logoSource != 'blocked_mismatch' &&
        resolvedRef.isNotEmpty;
    debugPrint(
      '[DRIVER_BRAND][RESOLVE] source=$brandSource active_company=${_maskCompanyIdForBrandLog(activeCompanyId)} brand_company=${_maskCompanyIdForBrandLog(brandCompanyId)} logo=${logoPresent ? 'present' : 'missing'} logo_source=$logoSource',
    );
    return resolvedRef;
  }

  void _setNavigationWakelock(bool enabled) {
    if (_navigationWakelockEnabled == enabled) return;
    _navigationWakelockEnabled = enabled;
    final op = enabled ? WakelockPlus.enable() : WakelockPlus.disable();
    unawaited(
      op.catchError((Object e, StackTrace st) {
        debugPrint('[WAKELOCK][WARN] enabled=$enabled error=$e');
      }),
    );
  }

  void _onAppLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onDriverThemeSourceChanged() {
    if (!mounted) return;
    chauffeurShellFrameThemeNotifier.value = _activeDriverThemeListenable.value;
    setState(() {});
  }

  void _onDriverHomeMobileLayoutChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Widget _tenantLogo({
    required double height,
    BoxFit fit = BoxFit.contain,
    Widget? fallback,
  }) {
    bool isHttpImageRef(String value) {
      final lower = value.trim().toLowerCase();
      return lower.startsWith('https://') || lower.startsWith('http://');
    }

    Widget resolvedFallback() {
      return fallback ??
          Image.asset(
            kFluxidiLogoAsset,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.local_taxi, size: 72, color: Colors.white70),
          );
    }

    return ValueListenableBuilder<ActiveDriverSession?>(
      valueListenable: activeDriverSessionNotifier,
      builder: (context, session, _) {
        return ValueListenableBuilder<BusinessSettingsState>(
          valueListenable: businessSettingsNotifier,
          builder: (context, businessSettings, __) {
            final ref =
                _resolveDriverHomeBrandLogoRef(
                  businessSettings: businessSettings,
                  session: session,
                ) ??
                kFluxidiLogoAsset;
            if (_isAssetRef(ref)) {
              return Image.asset(
                ref,
                height: height,
                fit: fit,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, ___, ____) => resolvedFallback(),
              );
            }
            if (isHttpImageRef(ref)) {
              return Image.network(
                ref,
                height: height,
                fit: fit,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, ___, ____) => resolvedFallback(),
              );
            }
            if (kIsWeb) return resolvedFallback();
            return Image.file(
              File(ref),
              height: height,
              fit: fit,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, ___, ____) => resolvedFallback(),
            );
          },
        );
      },
    );
  }

  String _driverAssetByTheme({
    required String defaultAsset,
    String? midnightBlueAsset,
    String? middayGoldAsset,
  }) {
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    if (isMidnightBlue && (midnightBlueAsset ?? '').trim().isNotEmpty) {
      return midnightBlueAsset!;
    }
    if (isMiddayGold && (middayGoldAsset ?? '').trim().isNotEmpty) {
      return middayGoldAsset!;
    }
    return defaultAsset;
  }

  LinearGradient _middayGoldMetallicGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFFFFF0B8).withOpacity(0.90),
        const Color(0xFFE8C57E).withOpacity(0.78),
        const Color(0xFF8A7040).withOpacity(0.72),
        const Color(0xFFFFDFA3).withOpacity(0.86),
      ],
      stops: const [0.0, 0.35, 0.68, 1.0],
    );
  }

  Widget _middayGoldGradientFrame({
    required Widget child,
    required double radius,
    double stroke = 1.0,
    Color innerColor = Colors.transparent,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: _middayGoldMetallicGradient(),
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: EdgeInsets.all(stroke),
      child: Container(
        decoration: BoxDecoration(
          color: innerColor,
          borderRadius: BorderRadius.circular(math.max(0.0, radius - stroke)),
        ),
        child: child,
      ),
    );
  }

  Color _middayGoldBorderColor([double opacity = 0.48]) =>
      const Color(0xFFFFDFA3).withOpacity(opacity);

  Color _middayGoldTextPrimary() => const Color(0xFFFFF0D0);
  Color _middayGoldTextMuted() => const Color(0xFFE1CCA0);
  Color _middayGoldTextOnSelected() => const Color(0xFF2B2113);

  Color _midnightBlueAccent() => const Color(0xFF4DA3FF);
  Color _midnightBlueTextPrimary() => const Color(0xFFEAF6FF);
  Color _midnightBlueTextMuted() => const Color(0xFFAFCBEA);
  Color _midnightBlueBorderColor([double opacity = 0.46]) =>
      _midnightBlueAccent().withOpacity(opacity);

  LinearGradient _midnightBlueSurfaceGradient({bool soft = false}) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: soft
          ? const [Color(0xFF0A172B), Color(0xFF0D203A), Color(0xFF102A4D)]
          : const [Color(0xFF07111F), Color(0xFF0B1B33), Color(0xFF102A4D)],
    );
  }

  LinearGradient _midnightBlueSelectedSurfaceGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF1B4F9C).withOpacity(0.92),
        const Color(0xFF0B2D5C).withOpacity(0.88),
        const Color(0xFF061A35).withOpacity(0.92),
      ],
    );
  }

  LinearGradient _middayGoldSurfaceGradient({bool soft = false}) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: soft
          ? const [Color(0xFF21170D), Color(0xFF3A2B18), Color(0xFF6F5528)]
          : const [Color(0xFF17110A), Color(0xFF2C2113), Color(0xFF4A371C)],
    );
  }

  LinearGradient _middayGoldSelectedSurfaceGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFFF6E8C2).withOpacity(0.96),
        const Color(0xFFD8BF7B).withOpacity(0.88),
        const Color(0xFF8D7448).withOpacity(0.72),
        const Color(0xFF3A2A10).withOpacity(0.80),
      ],
    );
  }

  BoxDecoration _middayGoldCardDecoration({
    required double radius,
    bool selected = false,
    bool elevated = true,
    double borderOpacity = 0.52,
  }) {
    return BoxDecoration(
      gradient: selected
          ? _middayGoldSelectedSurfaceGradient()
          : _middayGoldSurfaceGradient(),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _middayGoldBorderColor(borderOpacity)),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: const Color(
                  0x66000000,
                ).withOpacity(selected ? 0.92 : 0.68),
                blurRadius: selected ? 8 : 7,
                offset: const Offset(0, 3),
              ),
            ]
          : null,
    );
  }

  ButtonStyle _middayGoldOutlinedActionButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: _middayGoldTextPrimary(),
      side: BorderSide(color: _middayGoldBorderColor(0.60), width: 1.1),
      backgroundColor: const Color(0x26332214),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ).copyWith(
      overlayColor: MaterialStateProperty.all(
        const Color(0xFFD8BF7B).withOpacity(0.24),
      ),
    );
  }

  ButtonStyle _middayGoldFilledActionButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: const Color(0xFF4A371C),
      foregroundColor: _middayGoldTextPrimary(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ).copyWith(
      side: MaterialStateProperty.all(
        BorderSide(color: _middayGoldBorderColor(0.66), width: 1.1),
      ),
      shadowColor: MaterialStateProperty.all(
        const Color(0x66000000).withOpacity(0.58),
      ),
      elevation: MaterialStateProperty.all(0),
      overlayColor: MaterialStateProperty.all(
        const Color(0xFFFFE7A8).withOpacity(0.18),
      ),
    );
  }

  ButtonStyle _midnightBlueOutlinedActionButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: _midnightBlueTextPrimary(),
      side: BorderSide(color: _midnightBlueBorderColor(0.62), width: 1.1),
      backgroundColor: const Color(0x1408111F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ).copyWith(
      overlayColor: MaterialStateProperty.all(
        _midnightBlueAccent().withOpacity(0.20),
      ),
    );
  }

  ButtonStyle _midnightBlueFilledActionButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: const Color(0xFF0A2345),
      foregroundColor: _midnightBlueTextPrimary(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ).copyWith(
      side: MaterialStateProperty.all(
        BorderSide(color: _midnightBlueBorderColor(0.68), width: 1.1),
      ),
      shadowColor: MaterialStateProperty.all(
        const Color(0x66000000).withOpacity(0.55),
      ),
      elevation: MaterialStateProperty.all(0),
      overlayColor: MaterialStateProperty.all(
        _midnightBlueAccent().withOpacity(0.18),
      ),
    );
  }

  // ===============================
  // JSON helpers (local)
  // ===============================
  dynamic _getNested(dynamic root, List<String> path) {
    dynamic cur = root;
    for (final k in path) {
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return null;
      }
    }
    return cur;
  }

  int? _toIntOrNullLocal(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  // Best-effort: hydrate missing booking fields via Tracking API Worker /track/booking (GET).
  // This endpoint exists on fluxidi-tracking-api (V2):
  //   GET /track/booking?booking_id=TEST-001
  // and returns pickup/dropoff + session status + last ping.
  Future<void> _hydrateActiveBookingDetails(String bookingId) async {
    try {
      final uri = _withActiveBookingScope(
        kWorkerBaseUrl,
        kGetBookingPath,
        extraQuery: <String, String>{'booking_id': bookingId},
      );
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['ok'] != true) return;

      // Tracking API returns flat fields
      final pickup = decoded['pickup']?.toString();
      final dropoff = decoded['dropoff']?.toString();
      final sessionId = decoded['session_id']?.toString();
      final status = decoded['status']?.toString();

      if (!mounted) return;

      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(
            from: pickup ?? _activeBooking!.from,
            to: dropoff ?? _activeBooking!.to,
            sessionId: sessionId ?? _activeBooking!.sessionId,
            status: status ?? _activeBooking!.status,
            details: <String, dynamic>{
              ..._activeBooking!.details,
              'tracking_booking': decoded,
            },
          );
        }

        final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
        if (idx >= 0) {
          _bookings[idx] = _bookings[idx].copyWith(
            from: pickup ?? _bookings[idx].from,
            to: dropoff ?? _bookings[idx].to,
            sessionId: sessionId ?? _bookings[idx].sessionId,
            status: status ?? _bookings[idx].status,
            details: <String, dynamic>{
              ..._bookings[idx].details,
              'tracking_booking': decoded,
            },
          );
        }
      });
    } catch (_) {
      // silent best-effort
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[MAP][HOSTING_MODE] mode=HC textureView=true');
    final initialStyle = _styleForMode(_cameraMode);
    _activeMapStyleUri = initialStyle;
    _stableMapWidget = mb.MapWidget(
      key: const ValueKey('mapbox_map'),
      onMapCreated: _onMapCreated,
      textureView: kDriverMapTextureView,
      androidHostingMode: kDriverMapHostingMode,
      styleUri: initialStyle,
      cameraOptions: mb.CameraOptions(
        center: _mbPoint(
          kDriverMapInitialCenterLon,
          kDriverMapInitialCenterLat,
        ),
        zoom: kDriverMapInitialZoom,
      ),
    );
    appLanguageNotifier.addListener(_onAppLanguageChanged);
    _activeDriverThemeListenable.addListener(_onDriverThemeSourceChanged);
    chauffeurShellFrameThemeNotifier.value = _activeDriverThemeListenable.value;
    fluxidiPendingPaymentNotifier.addListener(_onPendingPaymentStatusChanged);
    driverHomeMobileLayoutNotifier.addListener(
      _onDriverHomeMobileLayoutChanged,
    );

    _splashAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _splashPulse = CurvedAnimation(
      parent: _splashAnimCtrl,
      curve: Curves.easeInOut,
    );

    _activePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _activePulse = CurvedAnimation(
      parent: _activePulseCtrl,
      curve: Curves.easeInOut,
    );

    unawaited(NavDiagnosticsRecorder.instance.ensureInitialized());
    _bootStartedAt = DateTime.now();
    // Minimum splash duration so it feels intentional (not a flicker)
    // Christophe wants it to linger a bit longer for a more premium feel.
    Timer(const Duration(milliseconds: 8000), () {
      if (!mounted) return;
      _bootMinElapsed = true;
      _maybeHideBootSplash();
    });
    unawaited(_restoreBusinessPreviewDriverSelectionOnOpen());
    _syncDriverRideScopeContext(reason: 'init_state');
    if (widget.openedFromBusinessHome) {
      debugPrint('[DRIVER_VIEW_ORIGIN][BUSINESS_PREVIEW_SESSION_BYPASS]');
      debugPrint(
        '[DRIVER_SESSION][SKIP_STANDALONE_VALIDATION] reason=business_preview',
      );
    }
    _driversNotifierListener = () {
      if (!mounted) return;
      _reconcileDriverAvailability(source: 'local', reason: 'drivers_notifier');
    };
    driversNotifier.addListener(_driversNotifierListener!);
    // Seed the last-known photo cache from the current active session so the
    // avatar can preserve the driver photo across short session-null windows
    // (theme switch, navigation, restore-in-progress) without falling back
    // to the generic "fluxidi_driver_01" / unknown avatar.
    {
      final initialSession = activeDriverSessionNotifier.value;
      _rememberLastKnownDriverPhoto(
        initialSession?.driverId,
        initialSession?.driverPhotoUrl,
      );
    }
    _activeDriverSessionListener = () {
      if (!mounted) return;
      final session = activeDriverSessionNotifier.value;
      _rememberLastKnownDriverPhoto(session?.driverId, session?.driverPhotoUrl);
      // Trigger rebuild so the avatar swaps to the freshly restored photo.
      setState(() {});
    };
    activeDriverSessionNotifier.addListener(_activeDriverSessionListener!);
    _startDriverAvailabilityPolling(reason: 'init');
    // Business preview restore hydrates the preview driver/token and triggers its
    // own forced refresh; init_boot in parallel raced ahead without a token.
    if (!widget.openedFromBusinessHome) {
      _refreshBookings(trigger: 'init_boot');
    }
    unawaited(_refreshCompletedTodayCount(reason: 'init_boot'));
    unawaited(_refreshDriverAvailabilityFromBackend(reason: 'init_boot'));
    _startBookingPolling(reason: 'init');
    _renderDebugWindowTimer?.cancel();
    _renderDebugWindowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      debugPrint(
        '[RIDES][DEBUG_COUNTERS][MINUTE] bookingTimers=$_activeBookingRefreshTimerCount geolocatorSubs=$_activeGeolocatorSubscriptionCount mapRedrawPerMin=$_mapRedrawCountThisMinute routeRedrawPerMin=$_routeRedrawCountThisMinute',
      );
      _mapRedrawCountThisMinute = 0;
      _routeRedrawCountThisMinute = 0;
    });
  }

  void _startDriverAvailabilityPolling({required String reason}) {
    _driverAvailabilityPollTimer?.cancel();
    debugPrint(
      '[DRIVER_AVAILABILITY][POLL][START] reason=$reason intervalMs=${_driverAvailabilityPollInterval.inMilliseconds}',
    );
    _driverAvailabilityPollTimer = Timer.periodic(
      _driverAvailabilityPollInterval,
      (_) {
        if (!mounted) return;
        unawaited(
          _refreshDriverAvailabilityFromBackend(reason: 'periodic_poll'),
        );
      },
    );
  }

  void _stopDriverAvailabilityPolling({required String reason}) {
    _driverAvailabilityPollTimer?.cancel();
    _driverAvailabilityPollTimer = null;
    debugPrint('[DRIVER_AVAILABILITY][POLL][STOP] reason=$reason');
  }

  bool get _isBusinessPreviewMode => widget.openedFromBusinessHome;

  String _resolvedOperationalAvailabilityForDriver({DriverProfile? profile}) {
    final fromProfile = normalizeDriverAvailabilityState(
      profile?.availabilityStatus,
      fallback: _resolvedOperationalAvailability,
    );
    return fromProfile;
  }

  void _reconcileDriverAvailability({
    required String source,
    required String reason,
    String? incomingStatus,
  }) {
    final profile = _dashboardActiveDriverProfile();
    final oldStatus = normalizeDriverAvailabilityState(
      _resolvedOperationalAvailability,
      fallback: 'available',
    );
    final newStatus = normalizeDriverAvailabilityState(
      incomingStatus ?? profile?.availabilityStatus ?? oldStatus,
      fallback: oldStatus,
    );
    final paused = newStatus == 'paused';
    final changed = oldStatus != newStatus || _driverManualPause != paused;
    debugPrint(
      '[DRIVER_AVAILABILITY][REFRESH] driver=${_shortDriverIdForDiag(profile?.id ?? activeDriverSessionNotifier.value?.driverId ?? '')} status=$newStatus source=$source reason=$reason',
    );
    if (changed) {
      debugPrint(
        '[DRIVER_AVAILABILITY][RECONCILE] old=$oldStatus new=$newStatus source=$source reason=$reason',
      );
    }
    _resolvedOperationalAvailability = newStatus;
    if (_driverManualPause != paused) {
      _driverManualPause = paused;
      if (mounted) setState(() {});
    } else if (changed && mounted) {
      setState(() {});
    }
    if (_isBusinessPreviewMode) {
      debugPrint(
        '[DRIVER_VIEW_ORIGIN][BUSINESS_PREVIEW_STATUS] driver=${_shortDriverIdForDiag(profile?.id ?? '')} status=$newStatus',
      );
    }
    final action = _dashboardAvailabilityButtonAction(
      availabilityStatus: newStatus,
    );
    debugPrint(
      '[DRIVER_AVAILABILITY][BUTTON_STATE] driver=${_shortDriverIdForDiag(profile?.id ?? activeDriverSessionNotifier.value?.driverId ?? '')} status=$newStatus action=$action',
    );
  }

  Future<void> _refreshDriverAvailabilityFromBackend({
    required String reason,
    bool force = false,
  }) async {
    if (!mounted) return;
    if (_driverAvailabilityRefreshInFlight) return;
    final now = DateTime.now();
    if (!force &&
        _lastDriverAvailabilityRefreshAt != null &&
        now.difference(_lastDriverAvailabilityRefreshAt!) <
            _driverAvailabilityMinRefreshInterval) {
      return;
    }
    _lastDriverAvailabilityRefreshAt = now;
    _driverAvailabilityRefreshInFlight = true;
    try {
      final profile = _dashboardActiveDriverProfile();
      final session = activeDriverSessionNotifier.value;
      final driverId =
          profile?.id.trim() ??
          session?.driverId.trim() ??
          _effectiveActiveDriverIdForRideScope();
      if (driverId.isEmpty) return;

      var source = 'local';
      var resolvedStatus = normalizeDriverAvailabilityState(
        profile?.availabilityStatus,
        fallback: _resolvedOperationalAvailability,
      );

      if (_isBusinessPreviewMode) {
        final hydrated = await _hydrateCompanyBootstrapFromActiveSession(
          reason: 'driver_availability_$reason',
          bootstrapDriverSession: false,
        );
        if (hydrated) {
          source = 'company_bootstrap';
          final refreshed = _dashboardActiveDriverProfile();
          resolvedStatus = normalizeDriverAvailabilityState(
            refreshed?.availabilityStatus,
            fallback: resolvedStatus,
          );
        } else {
          final scope = _activeBusinessPreviewScope();
          final lookup = await fetchDriverOperationalAvailabilityStatus(
            driverId: driverId,
            tenantId: scope?.tenantId ?? session?.tenantId ?? '',
            companyId: scope?.companyId ?? session?.companyId ?? '',
            companySessionToken:
                activeCompanySessionNotifier.value?.companySessionToken,
          );
          if (lookup.ok) {
            source = lookup.source;
            resolvedStatus = lookup.availabilityStatus;
            if (profile != null &&
                lookup.availabilityStatus !=
                    normalizeDriverAvailabilityState(
                      profile.availabilityStatus,
                      fallback: 'available',
                    )) {
              updateDriver(
                profile.id,
                profile.copyWith(availabilityStatus: lookup.availabilityStatus),
                syncInventory: false,
              );
            }
          }
        }
      } else {
        final companyToken =
            activeCompanySessionNotifier.value?.companySessionToken;
        final lookup = await fetchDriverOperationalAvailabilityStatus(
          driverId: driverId,
          tenantId: session?.tenantId ?? '',
          companyId: session?.companyId ?? '',
          companySessionToken: companyToken,
        );
        if (lookup.ok) {
          source = lookup.source;
          resolvedStatus = lookup.availabilityStatus;
          final activeProfile = _dashboardActiveDriverProfile();
          if (activeProfile != null &&
              lookup.availabilityStatus !=
                  normalizeDriverAvailabilityState(
                    activeProfile.availabilityStatus,
                    fallback: 'available',
                  )) {
            updateDriver(
              activeProfile.id,
              activeProfile.copyWith(
                availabilityStatus: lookup.availabilityStatus,
              ),
              syncInventory: false,
            );
          }
        } else if (CompanySessionStore.instance.hasValidCompanyContext) {
          // Standalone: do not re-bootstrap driver session here — that runs
          // fleet validation that can no-op block UI even if non-destructive.
          // We only need company hydration to refresh availability lookups.
          final hydrated = await _hydrateCompanyBootstrapFromActiveSession(
            reason: 'driver_availability_$reason',
            bootstrapDriverSession: false,
          );
          if (hydrated) {
            source = 'company_bootstrap';
            final refreshed = _dashboardActiveDriverProfile();
            resolvedStatus = normalizeDriverAvailabilityState(
              refreshed?.availabilityStatus,
              fallback: resolvedStatus,
            );
          }
        }
      }

      if (!mounted) return;
      _reconcileDriverAvailability(
        source: source,
        reason: reason,
        incomingStatus: resolvedStatus,
      );
    } finally {
      _driverAvailabilityRefreshInFlight = false;
    }
  }

  void _syncDriverPauseFromProfile({required String reason}) {
    _reconcileDriverAvailability(source: 'local', reason: reason);
  }

  // ---------------------------------------------------------------------------
  // Mollie return-to-app + payment finalization fallback
  // ---------------------------------------------------------------------------
  // The deep-link listener, lifecycle observer, and /pay/status reconciliation
  // now live in `PaymentReturnCoordinator` (lib/payment_return.dart) and are
  // started once from main(), so they don't depend on this State being mounted.
  void _onPendingPaymentStatusChanged() {
    final pending = fluxidiPendingPaymentNotifier.value;
    if (!mounted || pending == null) return;
    if (pending.status != FluxidiPaymentStatus.confirmed) return;
    if (_lastPaymentConfirmationSnackbarId == pending.paymentBookingId) return;
    _lastPaymentConfirmationSnackbarId = pending.paymentBookingId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Betaling bevestigd. Je boeking is bevestigd.',
            en: 'Payment confirmed. Your booking is confirmed.',
            fr: 'Paiement confirme. Votre reservation est confirmee.',
            es: 'Pago confirmado. Tu reserva esta confirmada.',
          ),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preload the splash logo so we don't hit the errorBuilder fallback on first frame.
    // If the asset path is wrong, Flutter will throw during precache and we'll still fall back.
    unawaited(
      precacheImage(AssetImage(kFluxidiLogoAsset), context).catchError((_) {}),
    );
  }

  @override
  void dispose() {
    debugPrint('[MAP][DISPOSE] mounted=$mounted style=$_activeMapStyleUri');
    _markerSelfHealTimer?.cancel();
    _markerSelfHealTimer = null;
    _resetPendingFollowCamera();
    _setNavigationWakelock(false);
    appLanguageNotifier.removeListener(_onAppLanguageChanged);
    _activeDriverThemeListenable.removeListener(_onDriverThemeSourceChanged);
    driverHomeMobileLayoutNotifier.removeListener(
      _onDriverHomeMobileLayoutChanged,
    );
    if (_driversNotifierListener != null) {
      driversNotifier.removeListener(_driversNotifierListener!);
      _driversNotifierListener = null;
    }
    if (_activeDriverSessionListener != null) {
      activeDriverSessionNotifier.removeListener(_activeDriverSessionListener!);
      _activeDriverSessionListener = null;
    }
    _stopDriverAvailabilityPolling(reason: 'dispose');
    chauffeurShellFrameThemeNotifier.value = null;
    fluxidiPendingPaymentNotifier.removeListener(
      _onPendingPaymentStatusChanged,
    );
    _bookingsUiVersion.dispose();
    _splashAnimCtrl.dispose();
    _activePulseCtrl.dispose();
    _stopMeterTicker();
    _stopTrackingInternal();
    unawaited(
      NavDiagnosticsRecorder.instance.endSessionIfActive(reason: 'dispose'),
    );
    _stopBookingPolling(reason: 'dispose');
    _renderDebugWindowTimer?.cancel();
    _renderDebugWindowTimer = null;
    _resetNavR3MotionState();
    _resetNavCameraPolicyState();
    _resetNavConfidenceState();
    _resetNavComplexityState();
    _resetNavMotionPredictionState();
    _resetNavInstructionPolicyState();
    _manualFromCtrl.dispose();
    _manualToCtrl.dispose();
    _directRideDestinationText = null;
    _directRideDestinationPoint = null;
    _directRideEstimateDebounce?.cancel();
    _directRideEstimateLocationRetryTimer?.cancel();
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    _fromFocus.dispose();
    _toFocus.dispose();
    driverRideScopeActiveDriverIdOverride.value = '';
    driverRideScopeActiveVehicleIdOverride.value = '';
    super.dispose();
  }

  Map<String, String> _headers({bool admin = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (admin && kAdminToken.trim().isNotEmpty) {
      h['x-admin-token'] = kAdminToken.trim();
    }
    return h;
  }

  Future<Map<String, String>> _companyOwnerHeaders() async {
    final auth = await resolveCompanyOwnerAuthHeaders();
    return auth.headers;
  }

  /// Scope for driver History / completed-today fetches.
  ///
  /// Standalone driver mode must never inherit tenant/company from a stale
  /// company profile when the active driver session belongs to another company.
  ({String tenantId, String companyId, String source})?
  _strictDriverHistoryScopeIdsWithSource() {
    if (_isBusinessPreviewMode) {
      return _strictActiveLocalScopeIdsWithSource();
    }

    final driverSession = activeDriverSessionNotifier.value;
    final driverTenantId = (driverSession?.tenantId ?? '').trim();
    final driverCompanyId = (driverSession?.companyId ?? '').trim();
    final hasDriverScope =
        driverTenantId.isNotEmpty && driverCompanyId.isNotEmpty;
    final standaloneDriverView =
        appRoleNotifier.value == AppRole.driver ||
        (driverSession?.isStandaloneLoginSession ?? false);

    if (standaloneDriverView && hasDriverScope) {
      final companyProfileId =
          companyProfileNotifier.value?.companyId.trim() ?? '';
      final sessionCompanyId =
          activeCompanySessionNotifier.value?.companyId.trim() ?? '';
      if ((companyProfileId.isNotEmpty &&
              companyProfileId != driverCompanyId) ||
          (sessionCompanyId.isNotEmpty &&
              sessionCompanyId != driverCompanyId)) {
        debugPrint(
          '[DRIVER_HISTORY][SCOPE] reason=standalone_driver_session_over_company_context profile=${_maskLocalScopeId(companyProfileId)} session=${_maskLocalScopeId(sessionCompanyId)} driver_company=${_maskLocalScopeId(driverCompanyId)}',
        );
      }
      return (
        tenantId: driverTenantId,
        companyId: driverCompanyId,
        source: 'driver_session',
      );
    }

    return _strictActiveLocalScopeIdsWithSource();
  }

  Future<Map<String, String>> _tripsHistoryAuthHeaders({
    required String scopeSource,
    required String driverId,
    String fetchContext = 'history',
  }) async {
    final preferDriverSession = scopeSource.trim() == 'driver_session';
    final auth = await resolveTripsHistoryAuthHeaders(
      json: false,
      preferDriverSession: preferDriverSession,
    );
    final scopeLabel = switch (scopeSource.trim()) {
      'company_profile' || 'company_session' => 'company',
      'driver_session' => 'driver_session',
      _ => scopeSource.trim().isEmpty ? 'unknown' : scopeSource.trim(),
    };
    debugPrint(
      '[DRIVER_HISTORY][FETCH] context=$fetchContext auth_mode=${auth.fetchLogAuthMode} scope_source=$scopeLabel driver=${_maskLocalScopeId(driverId)}',
    );
    return auth.headers;
  }

  void _startBookingPolling({required String reason}) {
    if (_liveRideActive) {
      _stopBookingPolling(reason: 'tracking_started');
      return;
    }
    final fastListMode = _bookingsHubVisible && !_liveRideActive;
    final interval = fastListMode
        ? _bookingsPollIntervalFastList
        : _bookingsPollIntervalSafeLive;
    final mode = fastListMode ? 'fast_list' : 'safe_live';
    if (_bookingPollTimer != null &&
        _activeBookingPollIntervalMs == interval.inMilliseconds) {
      return;
    }
    _bookingPollTimer?.cancel();
    debugPrint(
      '[RIDES][POLL][MODE] mode=$mode intervalMs=${interval.inMilliseconds}',
    );
    _bookingPollTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      if (_liveRideActive) return;
      _refreshBookings(trigger: 'periodic_poll');
    });
    _activeBookingRefreshTimerCount = 1;
    _activeBookingPollIntervalMs = interval.inMilliseconds;
    debugPrint(
      '[RIDES][POLL][START] reason=$reason activeTimers=$_activeBookingRefreshTimerCount',
    );
  }

  void _stopBookingPolling({required String reason}) {
    if (_bookingPollTimer == null) return;
    _bookingPollTimer?.cancel();
    _bookingPollTimer = null;
    _activeBookingRefreshTimerCount = 0;
    _activeBookingPollIntervalMs = null;
    debugPrint(
      '[RIDES][POLL][STOP] reason=$reason activeTimers=$_activeBookingRefreshTimerCount',
    );
  }

  // F3-E: any of these signals means the user is currently looking at a
  // driver UI surface (real driver login, business_home preview, or the
  // driver-only bookings hub). When true, ride refreshes must prefer
  // /driver/bookings and never fall back to /bookings, otherwise
  // available_unassigned semantics are silently dropped.
  bool get _isInDriverUiContext {
    if (appRoleNotifier.value == AppRole.driver) return true;
    if (widget.openedFromBusinessHome) return true;
    if (_bookingsHubVisible) return true;
    if ((_businessPreviewDriverId ?? '').trim().isNotEmpty) return true;
    return false;
  }

  Future<void> _refreshBookings({
    bool force = false,
    String trigger = 'unknown',
  }) async {
    if (!mounted) return;
    if (_bookingsRefreshInFlight != null) {
      if (force) {
        // G3-L: a forced refresh arrived while one is already running. Do not
        // drop it — record exactly one pending follow-up trigger so the
        // _refreshBookings finally-block can drain it once the current run
        // settles. This is the fix for the business-preview entry race
        // where business_preview_restore (force=true) was being silently
        // skipped behind init_boot.
        if (_pendingFollowUpRefreshTrigger == null ||
            // Prefer the more specific business_preview/my_rides triggers if
            // they arrive after a generic queued trigger.
            trigger == 'business_preview_restore' ||
            trigger == 'my_rides_segment') {
          _pendingFollowUpRefreshTrigger = trigger;
        }
        debugPrint(
          '[DRIVER_RIDES][REFRESH_QUEUED] trigger=$trigger reason=in_flight queued=${_pendingFollowUpRefreshTrigger ?? trigger}',
        );
      } else {
        debugPrint('[RIDES][REFRESH][SKIP] reason=in_flight trigger=$trigger');
      }
      return _bookingsRefreshInFlight!;
    }
    final now = DateTime.now();
    final isManualTrigger =
        trigger == 'drawer_manual' || trigger == 'list_manual';
    if (force && isManualTrigger && _lastManualRefreshAt != null) {
      final elapsed = now.difference(_lastManualRefreshAt!);
      if (elapsed < _manualRefreshCooldown) {
        debugPrint(
          '[RIDES][REFRESH][SKIP] reason=manual_cooldown trigger=$trigger elapsedMs=${elapsed.inMilliseconds}',
        );
        return;
      }
    }
    if (force && isManualTrigger) {
      _lastManualRefreshAt = now;
    }

    final fastListMode = _bookingsHubVisible && !_liveRideActive;
    final minInterval = fastListMode
        ? _bookingsMinRefreshIntervalFastList
        : _bookingsMinRefreshIntervalSafeLive;
    final minIntervalReason = fastListMode
        ? 'min_interval_fast_list'
        : 'min_interval_safe_live';
    if (!force && _lastBookingsRefreshAt != null) {
      final elapsed = now.difference(_lastBookingsRefreshAt!);
      if (elapsed < minInterval) {
        debugPrint(
          '[RIDES][REFRESH][SKIP] reason=$minIntervalReason trigger=$trigger elapsedMs=${elapsed.inMilliseconds}',
        );
        return;
      }
    }
    if (force &&
        trigger == 'status_change' &&
        _lastStatusTriggeredRefreshAt != null) {
      final elapsed = now.difference(_lastStatusTriggeredRefreshAt!);
      if (elapsed < _statusRefreshCooldown) {
        debugPrint(
          '[RIDES][REFRESH][SKIP] reason=status_cooldown trigger=$trigger elapsedMs=${elapsed.inMilliseconds}',
        );
        return;
      }
    }
    if (force && trigger == 'status_change') {
      _lastStatusTriggeredRefreshAt = now;
    }
    _lastBookingsRefreshAt = now;
    if (force) {
      debugPrint('[DRIVER_RIDES][FORCE_REFRESH] trigger=$trigger');
    }
    final task = _performRefreshBookings(trigger: trigger);
    _bookingsRefreshInFlight = task;
    try {
      await task;
    } finally {
      _bookingsRefreshInFlight = null;
      // G3-L: drain queued follow-up trigger (e.g. business_preview_restore
      // queued behind init_boot). We unawait this on purpose: the awaiter of
      // the current call has already received its completion, and the
      // follow-up should be visible-but-not-blocking. _refreshBookings is
      // re-entrant safe via the in-flight guard above and the
      // _driverBookingsRefreshSeq stale-response guard inside
      // _performRefreshBookings.
      final pending = _pendingFollowUpRefreshTrigger;
      if (pending != null && mounted) {
        _pendingFollowUpRefreshTrigger = null;
        unawaited(_refreshBookings(force: true, trigger: pending));
      }
    }
  }

  Future<void> _performRefreshBookings({required String trigger}) async {
    if (!mounted) return;
    final mySeq = ++_driverBookingsRefreshSeq;
    setState(() {
      _loadingBookings = true;
      _bookingsError = null;
    });
    _markBookingsUiDirty();

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final activeDriverSession = activeDriverSessionNotifier.value;
      final driverSessionToken = (activeDriverSession?.driverSessionToken ?? '')
          .trim();
      // F3-E: thread driver UI context signals through the helpers so that
      // business_home preview and driver-only flows always pick the
      // /driver/bookings endpoint (or block /bookings) instead of silently
      // refreshing from the company list.
      final inDriverUiContext = _isInDriverUiContext;
      final previewDriverId = (_businessPreviewDriverId ?? '').trim();
      final effectiveDriverId = widget.openedFromBusinessHome
          ? _effectiveCurrentDriverIdForBusinessPreview()
          : (activeDriverSession?.driverId.trim() ?? '');
      final businessPreviewMode = widget.openedFromBusinessHome;
      Uri primaryUri;
      Map<String, String> requestHeaders;
      final useDriverEndpoint = _shouldUseDriverBookingsRefreshEndpoint(
        driverUiContext: inDriverUiContext,
        hubVisible: _bookingsHubVisible,
        previewDriverId: previewDriverId,
        effectiveDriverId: effectiveDriverId,
        businessPreviewMode: businessPreviewMode,
      );
      if (useDriverEndpoint) {
        if (driverSessionToken.isEmpty) {
          // F3-E: /driver/bookings requires a driver session token. If we are
          // in driver UI context but the token is missing (e.g. business_home
          // preview without a pairing session), do NOT fall back to
          // /bookings (which would lose available_unassigned semantics);
          // skip this refresh cycle so the previously observed state is
          // preserved by the F3-D PRESERVE_AVAILABLE_ON_EMPTY guard.
          debugPrint(
            '[RIDES][REFRESH][BLOCK_COMPANY_IN_DRIVER_CONTEXT] trigger=$trigger reason=no_driver_token',
          );
          if (!mounted) return;
          setState(() {
            _loadingBookings = false;
          });
          _markBookingsUiDirty();
          return;
        }
        if (appRoleNotifier.value != AppRole.driver) {
          final forceReason = previewDriverId.isNotEmpty
              ? 'business_preview'
              : (_bookingsHubVisible
                    ? 'hub_visible'
                    : (effectiveDriverId.isNotEmpty
                          ? 'effective_driver_id'
                          : 'driver_ui_context'));
          debugPrint(
            '[RIDES][REFRESH][FORCE_DRIVER_ENDPOINT] trigger=$trigger reason=$forceReason',
          );
        }
        // G2-B: thread explicit tenant/company/driver/employee scope onto the
        // /driver/bookings request when the active driver session carries
        // those identifiers. Backend auth still happens via the bearer token
        // and these params do not weaken /driver/bookings auth — they exist
        // so worker-side logs and any scope-aware backend code can attribute
        // the request to the right tenant/company/driver. Only values present
        // on the live ActiveDriverSession are sent; we never invent values.
        final scopeTenantId = (activeDriverSession?.tenantId ?? '').trim();
        final scopeCompanyId = (activeDriverSession?.companyId ?? '').trim();
        final scopeDriverId = effectiveDriverId.isNotEmpty
            ? effectiveDriverId
            : (activeDriverSession?.driverId ?? '').trim();
        final scopeVehicleId = _effectiveActiveVehicleIdForRideScope();
        final scopeEmployeeNumber = (activeDriverSession?.employeeNumber ?? '')
            .trim();
        final scopeQuery = <String, String>{};
        if (scopeTenantId.isNotEmpty) {
          scopeQuery['tenant_id'] = scopeTenantId;
          scopeQuery['tenantId'] = scopeTenantId;
        }
        if (scopeCompanyId.isNotEmpty) {
          scopeQuery['company_id'] = scopeCompanyId;
          scopeQuery['companyId'] = scopeCompanyId;
        }
        if (scopeDriverId.isNotEmpty) {
          scopeQuery['driver_id'] = scopeDriverId;
          scopeQuery['driverId'] = scopeDriverId;
        }
        if (scopeVehicleId.isNotEmpty) {
          scopeQuery['vehicle_id'] = scopeVehicleId;
          scopeQuery['vehicleId'] = scopeVehicleId;
        }
        if (scopeEmployeeNumber.isNotEmpty) {
          scopeQuery['employee_number'] = scopeEmployeeNumber;
          scopeQuery['employeeNumber'] = scopeEmployeeNumber;
        }
        debugPrint(
          '[DRIVER_RIDES][REQ_SCOPE] tenant=${_safeRefPreview(scopeTenantId)} company=${_safeRefPreview(scopeCompanyId)} driver=${_safeRefPreview(scopeDriverId)} vehicle=${_safeRefPreview(scopeVehicleId)} employee=${_safeRefPreview(scopeEmployeeNumber)}',
        );
        primaryUri = Uri.parse('$kBookingBaseUrl$kDriverBookingsPath').replace(
          queryParameters: <String, String>{
            ...scopeQuery,
            'limit': '50',
            't': '$ts',
          },
        );
        requestHeaders = <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $driverSessionToken',
        };
        debugPrint('[RIDES][REFRESH][MODE] source=driver_bookings');
        debugPrint('[DRIVER_RIDES][REQ_URL] $primaryUri');
      } else if (_shouldBlockCompanyBookingsListRefreshInDriverContext(
        bookingsHubVisible: _bookingsHubVisible,
        driverUiContext: inDriverUiContext,
        previewDriverId: previewDriverId,
        effectiveDriverId: effectiveDriverId,
        businessPreviewMode: businessPreviewMode,
      )) {
        debugPrint(
          '[RIDES][REFRESH][BLOCK_COMPANY_IN_DRIVER_CONTEXT] trigger=$trigger',
        );
        debugPrint(
          '[RIDES][REFRESH][SOURCE_GUARD] blocked company_bookings_refresh trigger=$trigger hub=$_bookingsHubVisible',
        );
        if (!mounted) return;
        setState(() {
          _loadingBookings = false;
        });
        _markBookingsUiDirty();
        return;
      } else {
        primaryUri = _withActiveBookingScope(
          kBookingBaseUrl,
          kListBookingsPath,
          extraQuery: <String, String>{'limit': '50', 't': '$ts'},
        );
        if (businessPreviewMode) {
          requestHeaders = await _companyOwnerHeaders();
          debugPrint(
            '[RIDES][REFRESH][MODE] source=company_bookings reason=business_preview',
          );
        } else {
          requestHeaders = _headers(admin: true);
          debugPrint('[RIDES][REFRESH][MODE] source=company_bookings');
        }
      }
      debugPrint('[RIDES][REFRESH][REQ] trigger=$trigger GET $primaryUri');
      final res = await http.get(primaryUri, headers: requestHeaders);
      debugPrint(
        '[RIDES][REFRESH][RES] code=${res.statusCode} body=${res.body}',
      );

      if (useDriverEndpoint && res.statusCode == 401) {
        debugPrint('[RIDES][REFRESH][AUTH_EXPIRED]');
        if (businessPreviewMode) {
          debugPrint(
            '[DRIVER_VIEW_ORIGIN][INVALID_SESSION_BLOCKED] source=business_preview',
          );
          if (!mounted) return;
          setState(() {
            _loadingBookings = false;
          });
          _markBookingsUiDirty();
          return;
        }
        _stopBookingPolling(reason: 'driver_token_auth_expired');
        if (!mounted) return;
        setState(() {
          _bookingsError = _tr(
            nl: 'Je chauffeurssessie is verlopen. Log opnieuw in.',
            en: 'Your driver session expired. Please log in again.',
            fr: 'Votre session chauffeur a expire. Reconnectez-vous.',
            es: 'Tu sesion de conductor ha caducado. Inicia sesion de nuevo.',
          );
          _loadingBookings = false;
        });
        _markBookingsUiDirty();
        return;
      }

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response');
      }

      // Worker variants:
      // - tracking-api V2: { ok, count, bookings:[...] }
      // - booking-worker tracking bridge: { ok, items:[...] }
      final raw =
          (decoded['bookings'] as List<dynamic>? ??
          decoded['items'] as List<dynamic>? ??
          const []);
      final prevStatusByRowKey = <String, String?>{
        for (final b in _bookings) b.rowKey: _effectiveStatusFor(b),
      };
      final prevStatusByBookingId = <String, String?>{
        for (final b in _bookings) b.bookingId: _effectiveStatusFor(b),
      };
      final prevItemsByRowKey = <String, BookingItem>{
        for (final b in _bookings) b.rowKey: b,
      };
      final prevItemsByBookingId = <String, BookingItem>{
        for (final b in _bookings) b.bookingId: b,
      };
      final items = raw.whereType<Map<String, dynamic>>().map((j) {
        final parsed = BookingItem.fromJson(j);
        final apiStatus = parsed.status?.trim();
        final mergedStatus = (apiStatus != null && apiStatus.isNotEmpty)
            ? apiStatus
            : (prevStatusByRowKey[parsed.rowKey] ??
                  prevStatusByBookingId[parsed.bookingId] ??
                  _bookingStatusOverrides[parsed.rowKey] ??
                  _bookingStatusOverrides[parsed.bookingId]);
        final withStatus = mergedStatus == null
            ? parsed
            : parsed.copyWith(status: mergedStatus);
        final previous =
            prevItemsByRowKey[withStatus.rowKey] ??
            prevItemsByBookingId[withStatus.bookingId];
        return _mergeDriverBookingRefreshItem(withStatus, previous);
      }).toList();

      // G2-B: surface available_unassigned arrivals in the parsed response so
      // it is obvious from logs whether the backend is returning them at all.
      // We log per booking (with masked id) so the count is visible without
      // dumping the full payload.
      for (final b in items) {
        if (_bookingItemIsBackendAvailableUnassigned(b)) {
          debugPrint(
            '[DRIVER_RIDES][AVAILABLE_UNASSIGNED_SEEN] booking=${_safeRefPreview(b.bookingId)}',
          );
        }
      }

      // F3-D: stale-response guard. If a newer refresh has begun while this
      // request was awaiting the network response, discard our stale result
      // before mutating any list/override state.
      if (mySeq != _driverBookingsRefreshSeq) {
        debugPrint(
          '[RIDES][REFRESH][STALE_IGNORED] seq=$mySeq latest=$_driverBookingsRefreshSeq',
        );
        return;
      }

      // F3-D: PRESERVE_AVAILABLE_ON_EMPTY. The /driver/bookings endpoint can
      // briefly return an empty list during backend reindex / availability
      // recomputation. Without this guard, available_unassigned rows visibly
      // disappear and reappear across refresh cycles. Only honored on the
      // driver endpoint, only when the response is empty, and only for rows
      // that are not contradicted by an explicit terminal update in the same
      // response (vacuous here because items is empty).
      if (useDriverEndpoint && items.isEmpty) {
        final preservedAvailable = _bookings
            .where(_bookingItemIsBackendAvailableUnassigned)
            .toList(growable: false);
        if (preservedAvailable.isNotEmpty) {
          final terminalIdsInResponse = <String>{
            for (final b in items)
              if (_isClosedRideStatus(_effectiveStatusFor(b))) b.bookingId,
          };
          final preserved = preservedAvailable
              .where((b) => !terminalIdsInResponse.contains(b.bookingId))
              .toList(growable: false);
          if (preserved.isNotEmpty) {
            debugPrint(
              '[RIDES][REFRESH][PRESERVE_AVAILABLE_ON_EMPTY] preserved=${preserved.length}',
            );
            if (!mounted) return;
            setState(() {
              _loadingBookings = false;
            });
            _markBookingsUiDirty();
            return;
          }
        }
      }

      final apiReturnedIds = items.map((e) => e.bookingId).toSet();
      _deletedBookingIds.removeWhere((id) => !apiReturnedIds.contains(id));
      for (final b in items) {
        final apiStatus = b.status?.trim();
        if (apiStatus != null && apiStatus.isNotEmpty) {
          _bookingStatusOverrides[b.rowKey] = apiStatus;
          if (!(b.isOperationalLeg && b.legId.trim().isNotEmpty)) {
            _bookingStatusOverrides[b.bookingId] = apiStatus;
          }
        }
      }

      final parsedStatuses = items
          .map(
            (b) =>
                '${_safeRefPreview(b.rowKey)}:${(_effectiveStatusFor(b) ?? 'null').toUpperCase()}',
          )
          .join(', ');
      final visibleStatuses = items
          .where((b) => !_deletedBookingIds.contains(b.bookingId))
          .where((b) => !_isClosedRideStatus(_effectiveStatusFor(b)))
          .map(
            (b) =>
                '${_safeRefPreview(b.rowKey)}:${(_effectiveStatusFor(b) ?? 'null').toUpperCase()}',
          )
          .join(', ');
      final visibleCount = items
          .where((b) => !_deletedBookingIds.contains(b.bookingId))
          .where((b) => !_isClosedRideStatus(_effectiveStatusFor(b)))
          .length;
      debugPrint(
        '[RIDES][REFRESH][PARSED] total=${items.length} visible=$visibleCount all=[$parsedStatuses] visibleOnly=[$visibleStatuses]',
      );

      if (!mounted) return;
      setState(() {
        _bookings = items;
        _loadingBookings = false;
      });
      _markBookingsUiDirty();
      _syncDriverRideScopeContext(reason: 'refresh_complete');
      _logRidesHubVisibleCounts(source: 'refresh_$trigger');
    } catch (e) {
      if (!mounted) return;
      // F3-D: do not overwrite a fresher response's state with a stale error.
      if (mySeq != _driverBookingsRefreshSeq) {
        debugPrint(
          '[RIDES][REFRESH][STALE_IGNORED] seq=$mySeq latest=$_driverBookingsRefreshSeq',
        );
        return;
      }
      setState(() {
        _bookingsError = e.toString();
        _loadingBookings = false;
      });
      _markBookingsUiDirty();
    } finally {
      _markBootFirstLoadDone();
    }
  }

  void _logDriverNavDiag({
    required String tag,
    required String action,
    String? bookingId,
  }) {
    final mode = _isBusinessPreviewMode ? 'business_preview' : 'standalone';
    final previewScope = _activeBusinessPreviewScope();
    final strictScope = _strictActiveBookingScopeQuery();
    final tenantPresent =
        (previewScope?.tenantId ?? strictScope?['tenant_id'] ?? '')
            .trim()
            .isNotEmpty;
    final companyPresent =
        (previewScope?.companyId ?? strictScope?['company_id'] ?? '')
            .trim()
            .isNotEmpty;
    final driverId = _resolvedActiveDriverIdForScope().trim();
    final safeBookingId = (bookingId ?? '').trim();
    debugPrint(
      '[DRIVER_NAV][$tag] action=$action mode=$mode '
      'booking_id=${safeBookingId.isNotEmpty ? _shortDriverIdForDiag(safeBookingId) : 'missing'} '
      'tenant=${tenantPresent ? 'present' : 'missing'} '
      'company=${companyPresent ? 'present' : 'missing'} '
      'driver_id=${driverId.isNotEmpty ? _shortDriverIdForDiag(driverId) : 'missing'}',
    );
  }

  /// Open a booking in "ride preview" mode:
  /// - show route in OVERVIEW
  /// - do NOT create a trip_id yet
  /// - driver presses START on the map to begin tracking + streetview/follow cam
  Future<void> _goToRide(BookingItem b) async {
    try {
      final bookingId = b.bookingId.trim();
      if (!_canOperateBookingWithGuard(
        _bookingScopeViewFor(b),
        action: 'open_ride',
      )) {
        _logDriverNavDiag(
          tag: 'BLOCK',
          action: 'open_ride',
          bookingId: bookingId,
        );
        return;
      }
      _logDriverNavDiag(
        tag: 'OPEN_RIDE',
        action: 'open_ride',
        bookingId: bookingId,
      );

      final fromBookingsHub = _bookingsHubVisible;
      // Prevent old bookings-hub optimized panel from flashing during
      // route pop/transition back to map/cockpit.
      if (_bookingsHubVisible) {
        if (mounted) {
          setState(() => _bookingsHubVisible = false);
        } else {
          _bookingsHubVisible = false;
        }
      }
      // We are typically called from the Bookings Hub page.
      // UX: return to the main map/cockpit immediately.
      if (_isBusinessPreviewMode) {
        // DriverHome sits on BusinessHome — never pop past the cockpit route.
        if (fromBookingsHub && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _logDriverNavDiag(
          tag: 'BUSINESS_PREVIEW_KEEP_DRIVER',
          action:
              'open_ride_pop=${fromBookingsHub ? 'bookings_hub_only' : 'none'}',
          bookingId: bookingId,
        );
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }

      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }

      setState(() {
        _activeBooking = b;
        _activeTripId = null;
        _activeDirectTripId = null;
        _directRideActive = false;
        _directRideDestinationText = null;
        _directRideDestinationPoint = null;
        _isStartingTrip = false;
        _routePhase = _RideRoutePhase.toPickup;

        _kmDriven = 0.0;
        _pingCount = 0;
        _lastPing = '—';

        _resetNavProgressState(clearRoute: true);

        _cameraMode = _CameraMode.overview;
        _hasSwitchedToFollow = false;
        _followCar = false;
        _allowOverviewCamera = true;

        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;

        _trackingStartedAt = null;
      });
      _setNavigationWakelock(true);
      await _applyMapStyleForMode();

      await _hydrateActiveBookingDetails(b.bookingId);
      await _hydrateActiveBookingPrice(b.bookingId);
      await _ensureLocationPermission();
      if (_lastPos == null) {
        try {
          final pos = await geo.Geolocator.getCurrentPosition(
            desiredAccuracy: geo.LocationAccuracy.best,
          );
          if (mounted) {
            setState(() => _lastPos = pos);
          } else {
            _lastPos = pos;
          }
        } catch (_) {
          // best-effort: fallback route logic below remains safe
        }
      }

      // Start location stream for map + marker (pings are guarded by _activeTripId).
      _startTrackingInternal();

      final bb = _activeBooking ?? b;
      await _buildOverviewRoute(bb);

      // Stay in overview mode after opening a booking.
      // Driver explicitly presses START to begin an active tracking session & follow-cam.

      if (mounted) setState(() => _isStartingTrip = false);
    } catch (e) {
      _toast('Open ride failed: $e');
    }
  }

  void _clearActiveSelection() {
    _stopTrackingInternal();
    unawaited(
      _clearActiveRouteAndNavigationState(
        reason: 'manual_clear_selection',
        bookingId: _activeBooking?.bookingId,
        clearActiveSelection: true,
      ),
    );
  }

  void _showMissingStrictBookingScopeSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Backend synchronisatie vereist een actieve bedrijfssessie. Herkoppel of herstel eerst uw bedrijf.',
            en: 'Backend synchronization requires an active company session. Relink or recover your company first.',
            fr: 'La synchronisation backend nécessite une session entreprise active. Reliez ou récupérez d abord votre entreprise.',
            es: 'La sincronizacion del backend requiere una sesion activa de empresa. Vuelve a vincular o recuperar tu empresa primero.',
          ),
        ),
      ),
    );
  }

  Map<String, String>? _strictBookingScopeForMutation({
    required String action,
    bool showUx = true,
  }) {
    final strictScope = _strictActiveBookingScopeQuery();
    if (strictScope != null) return strictScope;
    debugPrint(
      '[DRIVER_BOOKING_SCOPE][BLOCK] reason=missing_strict_booking_scope action=$action',
    );
    if (showUx) _showMissingStrictBookingScopeSnackbar();
    return null;
  }

  Uri _uriWithScope(String baseUrl, String path, Map<String, String> scope) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: scope);
  }

  ({String tenantId, String companyId})? _complianceLedgerScopeForStop() {
    final strictBookingScope = _strictActiveBookingScopeQuery();
    if (strictBookingScope != null) {
      final tenantId =
          (strictBookingScope['tenant_id'] ??
                  strictBookingScope['tenantId'] ??
                  '')
              .trim();
      final companyId =
          (strictBookingScope['company_id'] ??
                  strictBookingScope['companyId'] ??
                  '')
              .trim();
      if (tenantId.isNotEmpty && companyId.isNotEmpty) {
        return (tenantId: tenantId, companyId: companyId);
      }
    }
    return _strictActiveLocalScopeIds();
  }

  Future<void> _startTrip(BookingItem b) async {
    try {
      if (!_canOperateBookingWithGuard(
        _bookingScopeViewFor(b),
        action: 'start_tracking',
      )) {
        return;
      }
      if (mounted) setState(() => _isStartingTrip = true);

      // UX rule: Start in Drawer → Drawer closes → Map becomes primary focus
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }
      final strictScope = _strictBookingScopeForMutation(action: 'start_trip');
      if (strictScope == null) {
        if (mounted) setState(() => _isStartingTrip = false);
        return;
      }
      final uri = _uriWithScope(kWorkerBaseUrl, kStartTripPath, strictScope);
      final actorDriverId = _resolvedActiveDriverIdForScope().trim();
      final vehicleContext = _plannedTripActorVehicleContext(b);
      final actorVehicleId = vehicleContext.actorVehicleId.trim();
      debugPrint(
        '[PLANNED_TRIP][START][IDENTITY] booking=${_shortDriverIdForDiag(b.bookingId)} driver=${_shortDriverIdForDiag(actorDriverId)} vehicle=${_shortDriverIdForDiag(actorVehicleId)} vehicle_source=${vehicleContext.source}',
      );
      final payload = {
        'booking_id': b.bookingId,
        'driver_id': actorDriverId,
        'driverId': actorDriverId,
        'actor_driver_id': actorDriverId,
        'actorDriverId': actorDriverId,
        'vehicle_id': actorVehicleId,
        'vehicleId': actorVehicleId,
        'actor_vehicle_id': actorVehicleId,
        'actorVehicleId': actorVehicleId,
        ...strictScope,
        // Optional context (helps debugging / future UI)
        'pickup': (b.from ?? '').toString(),
        'dropoff': (b.to ?? '').toString(),
        'origin': _currentOriginPayload(_lastPos),
        'client_started_at': DateTime.now().toUtc().toIso8601String(),
        ..._driverMutationActorFields(
          actorDriverId: actorDriverId,
          actorVehicleId: actorVehicleId,
        ),
      };

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final sessionId = (j['session_id'] ?? j['sessionId'] ?? '').toString();
      if (sessionId.isEmpty)
        throw Exception('No session_id returned by Worker.');

      setState(() {
        _activeTripId = sessionId;
        _activeDirectTripId = null;
        _activeBooking = b;
        _directRideActive = false;
        _directRideDestinationText = null;
        _directRideDestinationPoint = null;
        _routePhase = _RideRoutePhase.trip;
        _kmDriven = 0.0;
        _trackingStartedAt = DateTime.now();
        _pingCount = 0;
        _lastPing = '—';

        _resetNavProgressState(clearRoute: true);

        _cameraMode = _CameraMode.follow;
        _hasSwitchedToFollow = true;
        _followCar = true;
        _allowOverviewCamera = false;

        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;
      });
      _setNavigationWakelock(true);
      await _applyMapStyleForMode();

      // Fetch canonical booking details (incl. fixed price) for display
      await _hydrateActiveBookingDetails(b.bookingId);
      await _hydrateActiveBookingPrice(b.bookingId);

      await _ensureLocationPermission();

      _startTrackingInternal();
      _startMeterTicker();
      await _forceFollowCameraNow(caller: 'start_trip');
      final bb = _activeBooking ?? b;
      await _buildNavRouteToDestination(bb);
    } catch (e) {
      if (mounted) setState(() => _isStartingTrip = false);
      _toast('Start failed: $e');
    }
  }

  Future<void> _hydrateActiveBookingPrice(String bookingId) async {
    // Pricing is owned by the BOOKING Worker (not the tracking Worker).
    // If the booking isn't known there yet (e.g. TEST-xxx created only in tracking),
    // we just skip without breaking tracking.
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        kTrackingBookingPath,
      );
      final res = await http
          .post(
            uri,
            headers: _headers(admin: true),
            body: jsonEncode(<String, dynamic>{
              'booking_id': bookingId,
              ..._activeBookingScopeQuery(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['ok'] != true) return;

      bool isEmptyHydrationValue(dynamic value) {
        if (value == null) return true;
        if (value is String) return value.trim().isEmpty;
        if (value is Map) return value.isEmpty;
        if (value is Iterable) return value.isEmpty;
        return false;
      }

      Map<String, dynamic> mergeNonEmptyDetails(
        Map<String, dynamic> existing,
        Map<String, dynamic> incoming,
      ) {
        final next = <String, dynamic>{...existing};
        for (final entry in incoming.entries) {
          final incomingValue = entry.value;
          if (isEmptyHydrationValue(incomingValue)) continue;
          final existingValue = next[entry.key];
          if (existingValue is Map && incomingValue is Map) {
            next[entry.key] = mergeNonEmptyDetails(
              Map<String, dynamic>.from(existingValue),
              Map<String, dynamic>.from(incomingValue),
            );
          } else {
            next[entry.key] = incomingValue;
          }
        }
        return next;
      }

      BookingItem? hydratedActive;
      if (!mounted) return;
      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          hydratedActive = _activeBooking!.copyWith(
            details: mergeNonEmptyDetails(_activeBooking!.details, j),
          );
          _activeBooking = hydratedActive;
        }
      });

      final activeForPrice = hydratedActive ?? _activeBooking;
      if (activeForPrice == null || activeForPrice.bookingId != bookingId) {
        return;
      }

      num? resolved;
      if (activeForPrice.isOperationalLeg) {
        resolved = _driverDisplayPriceForBooking(activeForPrice);
      } else {
        final record = (j['record'] is Map)
            ? (j['record'] as Map).cast<String, dynamic>()
            : null;
        final quoteSource = j['quote'] ?? record?['quote'];
        final quote = (quoteSource is Map)
            ? quoteSource.cast<String, dynamic>()
            : null;
        final pricing = (quote != null && quote['pricing'] is Map)
            ? (quote['pricing'] as Map).cast<String, dynamic>()
            : null;

        num? pickNum(dynamic v) {
          if (v is num) return v;
          if (v is String) return num.tryParse(v.replaceAll(',', '.'));
          return null;
        }

        // Booking worker /quote shapes we've used across versions:
        // pricing: { price_incl_vat | total_price | total | amount | eur | price }
        // quote:   { price | total | total_price | amount | eur }
        final dynamic pMap = pricing;
        final num? price = (pMap is Map<String, dynamic>)
            ? (pickNum(pMap['price_incl_vat']) ??
                  pickNum(pMap['total_price']) ??
                  pickNum(pMap['total']) ??
                  pickNum(pMap['price']) ??
                  pickNum(pMap['amount']) ??
                  pickNum(pMap['eur']))
            : null;

        final num? fallbackFromQuote =
            pickNum(quote?['price']) ??
            pickNum(quote?['total_price']) ??
            pickNum(quote?['total']) ??
            pickNum(quote?['amount']) ??
            pickNum(quote?['eur']);

        resolved = price ?? fallbackFromQuote;
      }
      if (resolved == null) return;

      if (!mounted) return;
      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(
            price: resolved,
            currency: 'EUR',
          );
        }
      });
    } catch (_) {
      // silent
    }
  }

  bool _isRideMutationTransportError(Object err) {
    final text = err.toString().toLowerCase();
    return text.contains('clientsoftware caused connection abort') ||
        text.contains('connection abort') ||
        text.contains('connection reset') ||
        text.contains('socketexception') ||
        text.contains('timeoutexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('uri=https://');
  }

  Future<String?> _fetchAuthoritativeRideStatus(String bookingId) async {
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '$kListBookingsPath/${Uri.encodeComponent(bookingId)}',
      );
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      final direct = (decoded['status'] ?? '').toString().trim();
      if (direct.isNotEmpty) return direct.toUpperCase();
      final record = decoded['record'];
      if (record is Map) {
        final recordStatus = (record['status'] ?? '').toString().trim();
        if (recordStatus.isNotEmpty) return recordStatus.toUpperCase();
        final booking = record['booking'];
        if (booking is Map) {
          final bookingStatus = (booking['status'] ?? '').toString().trim();
          if (bookingStatus.isNotEmpty) return bookingStatus.toUpperCase();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setBookingStatus(BookingItem b, String status) async {
    if (!mounted) return;
    if (!_canOperateBookingWithGuard(
      _bookingScopeViewFor(b),
      action: 'status_$status',
    )) {
      return;
    }
    final bookingId = b.bookingId;
    final actionKey = _bookingActionKeyForUi(b);
    setState(() => _bookingActionInFlight.add(actionKey));
    _markBookingsUiDirty();
    try {
      final strictScope = _strictBookingScopeForMutation(
        action: 'set_booking_status',
      );
      if (strictScope == null) return;
      final uri = _uriWithScope(
        kBookingBaseUrl,
        '$kUpdateBookingStatusPath/${Uri.encodeComponent(bookingId)}/status',
        strictScope,
      );
      final payload = <String, dynamic>{
        'booking_id': bookingId,
        'status': status,
        ...strictScope,
        ..._driverMutationActorFields(
          actorVehicleId: _bookingScopeFirstText(
            _bookingScopeViewFor(b),
            const [
              ['assigned_vehicle_id'],
              ['assignedVehicleId'],
              ['vehicle_id'],
              ['vehicleId'],
              ['booking', 'assigned_vehicle_id'],
              ['booking', 'assignedVehicleId'],
              ['booking', 'vehicle_id'],
              ['booking', 'vehicleId'],
            ],
          ),
        ),
      };
      debugPrint(
        '[RIDES][STATUS][REQ] url=$uri payload=${jsonEncode(payload)}',
      );
      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      debugPrint(
        '[RIDES][STATUS][RES] code=${res.statusCode} body=${res.body}',
      );
      dynamic decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = null;
      }
      final ok = decoded is Map ? decoded['ok'] == true : false;
      if (res.statusCode != 200 || !ok) {
        throw Exception('HTTP ${res.statusCode}: status_update_failed');
      }

      if (!mounted) return;
      setState(() {
        _bookingStatusOverrides[bookingId] = status;
        final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
        if (idx >= 0) {
          _bookings[idx] = _bookings[idx].copyWith(status: status);
        }
        if (_activeBooking?.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(status: status);
        }
      });
      final normalizedStatus = status.trim().toUpperCase();
      final shouldRouteCleanup =
          _activeBooking?.bookingId == bookingId &&
          !_liveRideActive &&
          (normalizedStatus == 'COMPLETED' ||
              normalizedStatus == 'CANCELLED' ||
              normalizedStatus == 'DELETED');
      if (shouldRouteCleanup) {
        _stopTrackingInternal();
        _stopMeterTicker();
        await _clearActiveRouteAndNavigationState(
          reason: normalizedStatus.toLowerCase(),
          bookingId: bookingId,
          clearActiveSelection: true,
        );
      }
      _markBookingsUiDirty();
      _toast('✅ $status: ${b.shortId}');
      await _debugFetchBookingSnapshot(
        bookingId: bookingId,
        contextLabel: 'STATUS_AFTER_WRITE',
      );
      final authoritativeFields = await _fetchPaymentFieldsForHistory(
        bookingId,
      );
      if (authoritativeFields.isNotEmpty && mounted) {
        setState(() {
          final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
          if (idx >= 0) {
            final mergedDetails = _mergeBusinessReferencesIntoSource(
              source: Map<String, dynamic>.from(_bookings[idx].details),
              authoritative: authoritativeFields,
              canonicalBookingId: bookingId,
              tripId: null,
              sourceTag: 'status_after_write_booking_list',
            )..addAll(authoritativeFields);
            _bookings[idx] = _bookings[idx].copyWith(details: mergedDetails);
          }
          if (_activeBooking?.bookingId == bookingId) {
            final mergedDetails = _mergeBusinessReferencesIntoSource(
              source: Map<String, dynamic>.from(_activeBooking!.details),
              authoritative: authoritativeFields,
              canonicalBookingId: bookingId,
              tripId: null,
              sourceTag: 'status_after_write_active_booking',
            )..addAll(authoritativeFields);
            _activeBooking = _activeBooking!.copyWith(details: mergedDetails);
          }
        });
      }
      await _refreshBookings(force: true, trigger: 'status_change');
    } catch (e) {
      final normalizedStatus = status.trim().toUpperCase();
      if (_isRideMutationTransportError(e)) {
        final authoritative = await _fetchAuthoritativeRideStatus(bookingId);
        if (authoritative == normalizedStatus) {
          if (!mounted) return;
          setState(() {
            _bookingStatusOverrides[bookingId] = normalizedStatus;
            final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
            if (idx >= 0) {
              _bookings[idx] = _bookings[idx].copyWith(
                status: normalizedStatus,
              );
            }
            if (_activeBooking?.bookingId == bookingId) {
              _activeBooking = _activeBooking!.copyWith(
                status: normalizedStatus,
              );
            }
          });
          _markBookingsUiDirty();
          _toast('✅ $status: ${b.shortId}');
          await _refreshBookings(
            force: true,
            trigger: 'status_change_verified',
          );
          return;
        }
      }
      _toast(
        _tr(
          nl: 'Status bijwerken mislukt. Vernieuw en probeer opnieuw.',
          en: 'Status update failed. Refresh and try again.',
          fr: 'La mise a jour du statut a echoue. Actualisez puis reessayez.',
          es: 'No se pudo actualizar el estado. Actualiza e intentalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _bookingActionInFlight.remove(actionKey));
        _markBookingsUiDirty();
      }
    }
  }

  Future<void> _setOperationalLegStatus(BookingItem b, String status) async {
    if (!mounted) return;
    if (!_canOperateBookingWithGuard(
      _bookingScopeViewFor(b),
      action: 'leg_status_$status',
    )) {
      return;
    }
    final bookingId = b.bookingId.trim();
    final legId = b.legId.trim();
    if (bookingId.isEmpty || legId.isEmpty) {
      _toast(
        _tr(
          nl: 'Legstatus bijwerken mislukt. Vernieuw en probeer opnieuw.',
          en: 'Leg status update failed. Refresh and try again.',
          fr: 'La mise a jour du statut du trajet a echoue. Actualisez puis reessayez.',
          es: 'No se pudo actualizar el estado del tramo. Actualiza e intentalo de nuevo.',
        ),
      );
      return;
    }
    final actionKey = _bookingActionKeyForUi(b);
    setState(() => _bookingActionInFlight.add(actionKey));
    _markBookingsUiDirty();
    try {
      final strictScope = _strictBookingScopeForMutation(
        action: 'set_operational_leg_status',
      );
      if (strictScope == null) return;
      final uri = _uriWithScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}/legs/${Uri.encodeComponent(legId)}/status',
        strictScope,
      );
      final actorRole = appRoleNotifier.value == AppRole.driver
          ? 'driver'
          : 'admin';
      final payload = <String, dynamic>{
        'booking_id': bookingId,
        'leg_id': legId,
        'status': status,
        'actor_role': actorRole,
        'actorRole': actorRole,
        ...strictScope,
        ..._driverMutationActorFields(
          actorVehicleId: _bookingScopeFirstText(
            _bookingScopeViewFor(b),
            const [
              ['assigned_vehicle_id'],
              ['assignedVehicleId'],
              ['vehicle_id'],
              ['vehicleId'],
              ['booking', 'assigned_vehicle_id'],
              ['booking', 'assignedVehicleId'],
              ['booking', 'vehicle_id'],
              ['booking', 'vehicleId'],
            ],
          ),
        ),
      };
      debugPrint(
        '[RIDES][LEG_STATUS][REQ] url=$uri payload=${jsonEncode(payload)}',
      );
      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      debugPrint(
        '[RIDES][LEG_STATUS][RES] code=${res.statusCode} body=${res.body}',
      );
      dynamic decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = null;
      }
      final ok = decoded is Map ? decoded['ok'] == true : false;
      if (res.statusCode != 200 || !ok) {
        throw Exception('HTTP ${res.statusCode}: leg_status_update_failed');
      }

      if (!mounted) return;
      setState(() {
        _bookingStatusOverrides[b.rowKey] = status;
        final idx = _bookings.indexWhere((x) => x.rowKey == b.rowKey);
        if (idx >= 0) {
          _bookings[idx] = _bookings[idx].copyWith(status: status);
        }
        if (_activeBooking?.rowKey == b.rowKey) {
          _activeBooking = _activeBooking!.copyWith(status: status);
        }
      });
      _markBookingsUiDirty();
      _toast('✅ $status: ${b.shortId}');
      final normalizedStatus = status.trim().toUpperCase();
      if (normalizedStatus == 'COMPLETED') {
        await _recordOperationalLegPlannedStopBestEffort(b);
      }
      await _debugFetchBookingSnapshot(
        bookingId: bookingId,
        contextLabel: 'LEG_STATUS_AFTER_WRITE',
      );
      await _refreshBookings(force: true, trigger: 'leg_status_change');
    } catch (e) {
      _toast(
        _tr(
          nl: 'Legstatus bijwerken mislukt. Vernieuw en probeer opnieuw.',
          en: 'Leg status update failed. Refresh and try again.',
          fr: 'La mise a jour du statut du trajet a echoue. Actualisez puis reessayez.',
          es: 'No se pudo actualizar el estado del tramo. Actualiza e intentalo de nuevo.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _bookingActionInFlight.remove(actionKey));
        _markBookingsUiDirty();
      }
    }
  }

  String? _sanitizeOperationalTripIdentityToken(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    final sanitized = value
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (sanitized.isEmpty) return null;
    return sanitized.length > 96 ? sanitized.substring(0, 96) : sanitized;
  }

  String _operationalLegTypeToken(BookingItem b) {
    final explicit = _bookingScopeFirstText(_bookingScopeViewFor(b), const [
      ['leg_type'],
      ['legType'],
      ['booking', 'leg_type'],
      ['booking', 'legType'],
    ]);
    final normalized = (explicit ?? '').trim().toLowerCase();
    if (normalized == 'return') return 'return';
    return 'outbound';
  }

  num? _operationalLegDetailNum(
    Map<String, dynamic> details,
    List<List<String>> paths,
  ) {
    for (final path in paths) {
      dynamic cursor = details;
      for (final key in path) {
        if (cursor is Map && cursor.containsKey(key)) {
          cursor = cursor[key];
        } else {
          cursor = null;
          break;
        }
      }
      if (cursor is num) return cursor;
      if (cursor is String) {
        final parsed = num.tryParse(cursor.replaceAll(',', '.').trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  void _driverCollectOperationalLegMaps(
    Map<String, dynamic> details,
    List<Map<String, dynamic>> out,
  ) {
    void addFromList(dynamic raw) {
      if (raw is! List) return;
      for (final entry in raw) {
        if (entry is Map) {
          out.add(Map<String, dynamic>.from(entry));
        }
      }
    }

    addFromList(details['operational_legs']);
    addFromList(details['operationalLegs']);
    final record = details['record'];
    if (record is Map) {
      final recordMap = Map<String, dynamic>.from(record);
      addFromList(recordMap['operational_legs']);
      addFromList(recordMap['operationalLegs']);
      final nestedBooking = recordMap['booking'];
      if (nestedBooking is Map) {
        addFromList(nestedBooking['operational_legs']);
        addFromList(nestedBooking['operationalLegs']);
      }
    }
    final booking = details['booking'];
    if (booking is Map) {
      addFromList(booking['operational_legs']);
      addFromList(booking['operationalLegs']);
    }
  }

  List<Map<String, dynamic>> _driverOperationalLegMapsFromDetails(
    Map<String, dynamic> details,
  ) {
    final maps = <Map<String, dynamic>>[];
    _driverCollectOperationalLegMaps(details, maps);
    return maps;
  }

  num? _driverLegPriceFromOperationalLegMap(Map<String, dynamic> map) {
    return _operationalLegDetailNum(map, const [
      ['price_incl_vat'],
      ['priceInclVat'],
      ['leg_price_incl_vat'],
      ['legPriceInclVat'],
      ['amount'],
      ['total'],
    ]);
  }

  num? _driverParentPackageTotalFromDetails(Map<String, dynamic> details) {
    return _operationalLegDetailNum(details, const [
      ['parent_price_incl_vat'],
      ['parentPriceInclVat'],
      ['parent_total_price'],
      ['parentTotalPrice'],
      ['booking_total_eur'],
      ['quote', 'pricing', 'price_incl_vat'],
      ['quote', 'pricing', 'total_price'],
      ['record', 'quote', 'pricing', 'price_incl_vat'],
      ['record', 'quote', 'pricing', 'total_price'],
      ['booking', 'price_incl_vat'],
      ['record', 'booking', 'price_incl_vat'],
    ]);
  }

  num? _driverLegTypeSplitPriceFromDetails(
    Map<String, dynamic> details,
    String legType,
  ) {
    if (legType == 'return') {
      return _operationalLegDetailNum(details, const [
        ['price_incl_vat_return'],
        ['priceInclVatReturn'],
        ['return_price_eur'],
        ['booking', 'price_incl_vat_return'],
        ['booking', 'priceInclVatReturn'],
        ['record', 'booking', 'price_incl_vat_return'],
        ['record', 'booking', 'priceInclVatReturn'],
        ['quote', 'price_incl_vat_return'],
        ['quote', 'pricing_return', 'price_incl_vat'],
        ['record', 'quote', 'price_incl_vat_return'],
        ['record', 'quote', 'pricing_return', 'price_incl_vat'],
      ]);
    }
    return _operationalLegDetailNum(details, const [
      ['price_incl_vat_main'],
      ['priceInclVatMain'],
      ['outbound_price_eur'],
      ['booking', 'price_incl_vat_main'],
      ['booking', 'priceInclVatMain'],
      ['record', 'booking', 'price_incl_vat_main'],
      ['record', 'booking', 'priceInclVatMain'],
      ['quote', 'price_incl_vat_main'],
      ['quote', 'pricing_main', 'price_incl_vat'],
      ['record', 'quote', 'price_incl_vat_main'],
      ['record', 'quote', 'pricing_main', 'price_incl_vat'],
    ]);
  }

  /// Active ride amount for driver UI + persistence. Operational legs never
  /// fall back to parent/package totals unless no leg amount exists anywhere.
  double? _driverDisplayPriceForBooking(BookingItem b) {
    if (!b.isOperationalLeg) {
      final p = b.price;
      if (p != null && p.isFinite) return p.toDouble();
      return null;
    }

    final details = b.details;
    final legId = b.legId.trim();
    final legType = _operationalLegTypeToken(b);

    num? pickFinite(num? value) {
      if (value == null || !value.isFinite) return null;
      return value;
    }

    final rowLegPrice = pickFinite(
      _operationalLegDetailNum(details, const [
        ['leg_price_incl_vat'],
        ['legPriceInclVat'],
      ]),
    );
    if (rowLegPrice != null) return rowLegPrice.toDouble();

    for (final map in _driverOperationalLegMapsFromDetails(details)) {
      if (legId.isNotEmpty) {
        final entryLegId = (map['leg_id'] ?? map['legId'] ?? '')
            .toString()
            .trim();
        if (entryLegId != legId) continue;
      } else {
        final entryType = (map['leg_type'] ?? map['legType'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final normalized = entryType == 'return' ? 'return' : 'outbound';
        if (normalized != legType) continue;
      }
      final legPrice = pickFinite(_driverLegPriceFromOperationalLegMap(map));
      if (legPrice != null) return legPrice.toDouble();
    }

    final splitPrice = pickFinite(
      _driverLegTypeSplitPriceFromDetails(details, legType),
    );
    if (splitPrice != null) return splitPrice.toDouble();

    final segmentPrice = pickFinite(
      _operationalLegDetailNum(details, const [
        ['segment_price_eur'],
        ['segmentPriceEur'],
        ['booking', 'segment_price_eur'],
        ['booking', 'segmentPriceEur'],
      ]),
    );
    if (segmentPrice != null) return segmentPrice.toDouble();

    final parentTotal = pickFinite(
      _driverParentPackageTotalFromDetails(details),
    );
    final rawPrice = b.price;
    if (rawPrice != null && rawPrice.isFinite) {
      if (parentTotal == null ||
          rawPrice.toDouble() != parentTotal.toDouble()) {
        return rawPrice.toDouble();
      }
    }

    return null;
  }

  Future<void> _recordOperationalLegPlannedStopBestEffort(
    BookingItem booking,
  ) async {
    if (!mounted) return;
    if (!booking.isOperationalLeg) return;
    final bookingId = booking.bookingId.trim();
    final legId = booking.legId.trim();
    if (bookingId.isEmpty || legId.isEmpty) return;

    try {
      final strictScope = _strictBookingScopeForMutation(
        action: 'record_operational_leg_planned_stop',
        showUx: false,
      );
      if (strictScope == null) return;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final bookingScope = _bookingScopeViewFor(booking);
      final legType = _operationalLegTypeToken(booking);
      final parentBookingId =
          (_bookingScopeFirstText(bookingScope, const [
                    ['parent_booking_id'],
                    ['parentBookingId'],
                    ['booking', 'parent_booking_id'],
                    ['booking', 'parentBookingId'],
                  ]) ??
                  bookingId)
              .trim();
      final rowKey = booking.rowKey.trim();
      final tripSuffix =
          _sanitizeOperationalTripIdentityToken(legId) ??
          _sanitizeOperationalTripIdentityToken(rowKey);
      final deterministicTripId = tripSuffix == null || tripSuffix.isEmpty
          ? 'planned_$bookingId'
          : 'planned_${bookingId}_$tripSuffix';
      final actorVehicleId = _bookingScopeFirstText(bookingScope, const [
        ['assigned_vehicle_id'],
        ['assignedVehicleId'],
        ['vehicle_id'],
        ['vehicleId'],
        ['booking', 'assigned_vehicle_id'],
        ['booking', 'assignedVehicleId'],
        ['booking', 'vehicle_id'],
        ['booking', 'vehicleId'],
      ]);
      final segmentAmount =
          _driverDisplayPriceForBooking(booking) ??
          _operationalLegDetailNum(booking.details, const [
            ['leg_price_incl_vat'],
            ['legPriceInclVat'],
            ['segment_price_eur'],
            ['booking', 'leg_price_incl_vat'],
            ['booking', 'legPriceInclVat'],
          ]);
      final parentAmount = _operationalLegDetailNum(booking.details, const [
        ['parent_total_price'],
        ['parentTotalPrice'],
        ['parent_price_incl_vat'],
        ['parentPriceInclVat'],
        ['booking_total_eur'],
        ['booking', 'price_incl_vat'],
      ]);
      final pickupLat = _operationalLegDetailNum(booking.details, const [
        ['pickup_lat'],
        ['pickupLat'],
        ['from_lat'],
        ['fromLat'],
        ['origin', 'lat'],
        ['pickup', 'lat'],
      ]);
      final pickupLon = _operationalLegDetailNum(booking.details, const [
        ['pickup_lon'],
        ['pickupLon'],
        ['pickup_lng'],
        ['pickupLng'],
        ['from_lon'],
        ['fromLon'],
        ['from_lng'],
        ['fromLng'],
        ['origin', 'lon'],
        ['origin', 'lng'],
        ['pickup', 'lon'],
        ['pickup', 'lng'],
      ]);
      final dropoffLat = _operationalLegDetailNum(booking.details, const [
        ['dropoff_lat'],
        ['dropoffLat'],
        ['to_lat'],
        ['toLat'],
        ['destination', 'lat'],
        ['dropoff', 'lat'],
      ]);
      final dropoffLon = _operationalLegDetailNum(booking.details, const [
        ['dropoff_lon'],
        ['dropoffLon'],
        ['dropoff_lng'],
        ['dropoffLng'],
        ['to_lon'],
        ['toLon'],
        ['to_lng'],
        ['toLng'],
        ['destination', 'lon'],
        ['destination', 'lng'],
        ['dropoff', 'lon'],
        ['dropoff', 'lng'],
      ]);
      // Prefer trusted booking drop-off coordinates; otherwise fall back to the
      // live device GPS, since the driver is physically at this leg's drop-off
      // when stopping it. This keeps each leg's arrival coordinate (Chiron
      // aankomstpunt) leg-scoped and never inherits another leg's drop-off.
      final num? effectiveDropoffLat = dropoffLat ?? _lastPos?.latitude;
      final num? effectiveDropoffLon = dropoffLon ?? _lastPos?.longitude;
      final bool hasEffectiveDropoffCoords =
          effectiveDropoffLat != null && effectiveDropoffLon != null;
      final payload = <String, dynamic>{
        'trip_id': deterministicTripId,
        'booking_id': bookingId,
        'parent_booking_id': parentBookingId,
        'leg_id': legId,
        'leg_type': legType,
        'row_key': rowKey,
        ...strictScope,
        'driver_id': kDriverId,
        'vehicle_id': _directRideVehicleId(),
        'origin': <String, dynamic>{
          'label': (booking.from ?? _receiptText('currentLocation')).toString(),
          if (pickupLat != null) 'lat': pickupLat.toDouble(),
          if (pickupLon != null) 'lon': pickupLon.toDouble(),
        },
        'destination': <String, dynamic>{
          'label': (booking.to ?? booking.from ?? booking.shortId).toString(),
          if (hasEffectiveDropoffCoords) 'lat': effectiveDropoffLat.toDouble(),
          if (hasEffectiveDropoffCoords) 'lon': effectiveDropoffLon.toDouble(),
        },
        'booking_details': <String, dynamic>{
          ..._plannedBookingDetailsPayload(booking),
          'leg_id': legId,
          'legId': legId,
          'leg_type': legType,
          'legType': legType,
          'row_key': rowKey,
          'rowKey': rowKey,
          'parent_booking_id': parentBookingId,
          'parentBookingId': parentBookingId,
          'is_operational_leg': true,
          'isOperationalLeg': true,
          if (segmentAmount != null) 'segment_price_eur': segmentAmount,
          if (segmentAmount != null) 'leg_price_incl_vat': segmentAmount,
          if (segmentAmount != null) 'legPriceInclVat': segmentAmount,
          if (parentAmount != null) 'booking_total_eur': parentAmount,
        },
        'status': 'stopped',
        'started_at': nowIso,
        'stopped_at': nowIso,
        'km_total': 0,
        'wait_seconds_total': 0,
        if (segmentAmount != null) 'total_eur': segmentAmount.toDouble(),
        'currency': booking.currency ?? kDefaultCurrency,
        ..._driverMutationActorFields(actorVehicleId: actorVehicleId),
      };
      debugPrint(
        '[RIDES][LEG_STATUS][PLANNED_STOP][REQ] trip=$deterministicTripId booking=$bookingId leg=$legId type=$legType',
      );
      final res = await http
          .post(
            _uriWithScope(
              kWorkerBaseUrl,
              kRecordPlannedTripStopPath,
              strictScope,
            ),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      debugPrint(
        '[RIDES][LEG_STATUS][PLANNED_STOP][RES] code=${res.statusCode} trip=$deterministicTripId booking=$bookingId leg=$legId',
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (err) {
      debugPrint(
        '[RIDES][LEG_STATUS][PLANNED_STOP][WARN] booking=${booking.bookingId} leg=${booking.legId} err=$err',
      );
    }
  }

  Future<void> _deleteBooking(BookingItem b) async {
    if (!mounted) return;
    if (!_canOperateBookingWithGuard(
      _bookingScopeViewFor(b),
      action: 'delete_booking',
    )) {
      return;
    }
    final bookingId = b.bookingId;
    final actionKey = _bookingActionKeyForUi(b);
    setState(() => _bookingActionInFlight.add(actionKey));
    _markBookingsUiDirty();
    try {
      final strictScope = _strictBookingScopeForMutation(
        action: 'delete_booking',
      );
      if (strictScope == null) return;
      final uri = _uriWithScope(
        kBookingBaseUrl,
        '$kDeleteBookingPath/${Uri.encodeComponent(bookingId)}/delete',
        strictScope,
      );
      final payload = <String, dynamic>{
        'booking_id': bookingId,
        ...strictScope,
        ..._driverMutationActorFields(
          actorVehicleId: _bookingScopeFirstText(
            _bookingScopeViewFor(b),
            const [
              ['assigned_vehicle_id'],
              ['assignedVehicleId'],
              ['vehicle_id'],
              ['vehicleId'],
              ['booking', 'assigned_vehicle_id'],
              ['booking', 'assignedVehicleId'],
              ['booking', 'vehicle_id'],
              ['booking', 'vehicleId'],
            ],
          ),
        ),
      };
      debugPrint(
        '[RIDES][DELETE][REQ] url=$uri payload=${jsonEncode(payload)}',
      );

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
      debugPrint(
        '[RIDES][DELETE][RES] code=${res.statusCode} body=${res.body}',
      );

      final j = jsonDecode(res.body);
      if (res.statusCode != 200 || (j is Map && j['ok'] != true)) {
        throw Exception('Worker error: ${res.statusCode} ${res.body}');
      }

      if (!mounted) return;
      setState(() {
        _deletedBookingIds.add(bookingId);
        _bookingStatusOverrides[bookingId] = 'DELETED';
        _bookings.removeWhere((x) => x.bookingId == bookingId);
      });
      if (_activeBooking?.bookingId == bookingId) {
        _stopTrackingInternal();
        _stopMeterTicker();
        await _clearActiveRouteAndNavigationState(
          reason: 'delete',
          bookingId: bookingId,
          clearActiveSelection: true,
        );
      }
      if (!_liveRideActive) _setNavigationWakelock(false);
      _markBookingsUiDirty();
      _toast('🗑️ Verwijderd: ${b.shortId}');
      await _debugFetchBookingSnapshot(
        bookingId: bookingId,
        contextLabel: 'DELETE_AFTER_WRITE',
      );
      await _refreshBookings(force: true, trigger: 'delete_action');
    } catch (e) {
      _toast('❌ Delete failed: $e');
    } finally {
      if (mounted) {
        setState(() => _bookingActionInFlight.remove(actionKey));
        _markBookingsUiDirty();
      }
    }
  }

  Future<void> _confirmDelete(BookingItem b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rit verwijderen?'),
        content: Text(
          'This will remove the booking from the list (KV).\n\nID: ${b.bookingId}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, delete'),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteBooking(b);
  }

  Future<void> _archiveClosedRideByDelete({
    required String bookingId,
    required String status,
  }) async {
    try {
      final strictScope = _strictBookingScopeForMutation(
        action: 'archive_closed_ride_delete',
        showUx: false,
      );
      if (strictScope == null) return;
      final uri = _uriWithScope(
        kBookingBaseUrl,
        '$kDeleteBookingPath/${Uri.encodeComponent(bookingId)}/delete',
        strictScope,
      );
      final payload = <String, dynamic>{
        'booking_id': bookingId,
        ...strictScope,
      };
      debugPrint(
        '[RIDES][STATUS->DELETE][REQ] status=$status url=$uri payload=${jsonEncode(payload)}',
      );
      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
      debugPrint(
        '[RIDES][STATUS->DELETE][RES] code=${res.statusCode} body=${res.body}',
      );
      dynamic decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = null;
      }
      final ok = decoded is Map ? decoded['ok'] == true : false;
      if (res.statusCode == 200 && ok) {
        if (!mounted) return;
        setState(() {
          _deletedBookingIds.add(bookingId);
          _bookingStatusOverrides[bookingId] = 'DELETED';
          _bookings.removeWhere((x) => x.bookingId == bookingId);
        });
        _markBookingsUiDirty();
      }
    } catch (e) {
      debugPrint('[RIDES][STATUS->DELETE][WARN] $e');
    }
  }

  Future<void> _debugFetchBookingSnapshot({
    required String bookingId,
    required String contextLabel,
  }) async {
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 12));
      debugPrint(
        '[RIDES][$contextLabel][SNAPSHOT] url=$uri code=${res.statusCode} body=${res.body}',
      );
    } catch (e) {
      debugPrint('[RIDES][$contextLabel][SNAPSHOT][WARN] $e');
    }
  }

  Future<Map<String, dynamic>> _fetchPaymentFieldsForHistory(
    String bookingId,
  ) async {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    String? text(dynamic value) {
      final s = value?.toString().trim();
      if (s == null || s.isEmpty || s.toLowerCase() == 'null') return null;
      return s;
    }

    Map<String, dynamic> parsePayment(dynamic rootRaw) {
      final root = asMap(rootRaw);
      final data = asMap(root['data']);
      final record = asMap(root['record']);
      final booking = asMap(root['booking']);
      final dataRecord = asMap(data['record']);
      final dataBooking = asMap(data['booking']);
      final recordBooking = asMap(record['booking']);
      final dataRecordBooking = asMap(dataRecord['booking']);

      final paymentStatus = text(
        root['payment_status'] ??
            root['paymentStatus'] ??
            record['payment_status'] ??
            record['paymentStatus'] ??
            recordBooking['payment_status'] ??
            recordBooking['paymentStatus'] ??
            booking['payment_status'] ??
            booking['paymentStatus'] ??
            data['payment_status'] ??
            data['paymentStatus'] ??
            dataRecord['payment_status'] ??
            dataRecord['paymentStatus'] ??
            dataBooking['payment_status'] ??
            dataBooking['paymentStatus'] ??
            dataRecordBooking['payment_status'] ??
            dataRecordBooking['paymentStatus'],
      );
      final paidAt = text(
        root['paid_at'] ??
            root['paidAt'] ??
            record['paid_at'] ??
            record['paidAt'] ??
            booking['paid_at'] ??
            booking['paidAt'] ??
            data['paid_at'] ??
            data['paidAt'] ??
            dataRecord['paid_at'] ??
            dataRecord['paidAt'] ??
            dataBooking['paid_at'] ??
            dataBooking['paidAt'],
      );
      final paymentProvider = text(
        root['payment_provider'] ??
            root['paymentProvider'] ??
            record['payment_provider'] ??
            record['paymentProvider'] ??
            booking['payment_provider'] ??
            booking['paymentProvider'] ??
            data['payment_provider'] ??
            data['paymentProvider'] ??
            dataRecord['payment_provider'] ??
            dataRecord['paymentProvider'] ??
            dataBooking['payment_provider'] ??
            dataBooking['paymentProvider'],
      );
      final paymentId = text(
        root['payment_id'] ??
            root['paymentId'] ??
            record['payment_id'] ??
            record['paymentId'] ??
            booking['payment_id'] ??
            booking['paymentId'] ??
            data['payment_id'] ??
            data['paymentId'] ??
            dataRecord['payment_id'] ??
            dataRecord['paymentId'] ??
            dataBooking['payment_id'] ??
            dataBooking['paymentId'],
      );
      final maps = _referenceLookupMaps(<Map<String, dynamic>>[
        root,
        data,
        record,
        booking,
        dataRecord,
        dataBooking,
        recordBooking,
        dataRecordBooking,
      ]);
      final refs = _extractBusinessReferenceAliasesFromMaps(maps);

      return <String, dynamic>{
        if (paymentStatus != null) ...{
          'payment_status': paymentStatus,
          'paymentStatus': paymentStatus,
        },
        if (paidAt != null) ...{'paid_at': paidAt, 'paidAt': paidAt},
        if (paymentProvider != null) ...{
          'payment_provider': paymentProvider,
          'paymentProvider': paymentProvider,
        },
        if (paymentId != null) ...{
          'payment_id': paymentId,
          'paymentId': paymentId,
        },
        if (refs.receipt != null) ...{
          'receipt_reference': refs.receipt,
          'receiptReference': refs.receipt,
        },
        if (refs.planning != null) ...{
          'planning_reference': refs.planning,
          'planningReference': refs.planning,
        },
        if (refs.publicBooking != null) ...{
          'public_booking_reference': refs.publicBooking,
          'publicBookingReference': refs.publicBooking,
        },
        if (refs.booking != null) ...{
          'booking_reference': refs.booking,
          'bookingReference': refs.booking,
        },
        if (refs.publicRef != null) ...{
          'public_reference': refs.publicRef,
          'publicReference': refs.publicRef,
        },
      };
    }

    Future<Map<String, dynamic>> fetchAndParse(Uri uri) async {
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 300)
        return <String, dynamic>{};
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return <String, dynamic>{};

      final root = Map<String, dynamic>.from(decoded);
      final parsed = parsePayment(root);
      if (parsed.isNotEmpty) return parsed;
      return <String, dynamic>{};
    }

    try {
      final byId = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final parsedById = await fetchAndParse(byId);
      if (parsedById.isNotEmpty) return parsedById;
    } catch (_) {}

    return <String, dynamic>{};
  }

  void _enterWaitMode() {
    if (!_liveRideActive) return;
    if (_isWaiting) return;
    setState(() {
      _isWaiting = true;
      _waitStartedAt = DateTime.now();
    });
    debugPrint(
      '[METER][WAIT_START] km=${_kmDriven.toStringAsFixed(3)} waitSec=${_effectiveWaitElapsed.inSeconds} total=${_liveMeterTotalEur.toStringAsFixed(2)}',
    );
    _startMeterTicker();
    unawaited(
      _sendDirectTripWaitEvent(
        path: kDirectTripWaitStartPath,
        logLabel: 'WAIT_START',
        timestampKey: 'client_wait_started_at',
      ),
    );
  }

  void _exitWaitMode() {
    if (!_liveRideActive) return;
    if (!_isWaiting) return;
    final started = _waitStartedAt;
    setState(() {
      _isWaiting = false;
      _waitStartedAt = null;
      if (started != null) {
        _waitElapsed += DateTime.now().difference(started);
      }
    });
    debugPrint(
      '[METER][WAIT_RESUME] km=${_kmDriven.toStringAsFixed(3)} waitSec=${_effectiveWaitElapsed.inSeconds} total=${_liveMeterTotalEur.toStringAsFixed(2)}',
    );
    _startMeterTicker();
    unawaited(
      _sendDirectTripWaitEvent(
        path: kDirectTripWaitEndPath,
        logLabel: 'WAIT_END',
        timestampKey: 'client_wait_ended_at',
      ),
    );
  }

  void _startMeterTicker() {
    _meterTicker?.cancel();
    if (!_liveRideActive) return;
    _meterTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_liveRideActive) {
        _meterTicker?.cancel();
        _meterTicker = null;
        return;
      }
      _debugLiveMeter(reason: 'ticker');
      setState(() {});
    });
  }

  void _stopMeterTicker() {
    _meterTicker?.cancel();
    _meterTicker = null;
  }

  Duration get _effectiveWaitElapsed {
    if (_isWaiting && _waitStartedAt != null) {
      return _waitElapsed + DateTime.now().difference(_waitStartedAt!);
    }
    return _waitElapsed;
  }

  bool get _liveRideActive => _activeTripId != null || _directRideActive;
  bool get _directRideDraft =>
      !_directRideActive &&
      _activeTripId == null &&
      _activeBooking == null &&
      (_directRideDestinationText ?? '').trim().isNotEmpty;

  double? get _fixedBookingPriceEur {
    final b = _activeBooking;
    if (b == null) return null;
    return _driverDisplayPriceForBooking(b);
  }

  ({
    String source,
    double startFee,
    double perKm,
    double waitPerMin,
    double vatRate,
    String vatMode,
    String currency,
  })
  _resolveDirectRidePricing() {
    final settings = businessSettingsNotifier.value;
    final vat = localBackendTaxProfileNotifier.value;
    final base = settings.pricingBaseFare;
    final perKm = settings.pricingPerKm;
    final wait = settings.pricingWaitPerMinute;
    final settingsUsable =
        base.isFinite &&
        base >= 0 &&
        perKm.isFinite &&
        perKm >= 0 &&
        wait.isFinite &&
        wait >= 0;
    final source = settingsUsable ? 'settings' : 'fallback';
    final vatRateBase = vat?.vatRate ?? settings.pricingVatRate;
    final vatRate =
        (vatRateBase.isFinite ? vatRateBase : settings.pricingVatRate)
            .clamp(0.0, 1.0)
            .toDouble();
    var vatMode = (vat?.vatDisplayMode ?? settings.pricingVatMode)
        .trim()
        .toLowerCase();
    if (vatMode.isEmpty) vatMode = 'incl';
    if (vatMode != 'incl' && vatMode != 'excl') vatMode = 'incl';
    final currency = settings.defaultCurrency.trim().isEmpty
        ? kDefaultCurrency
        : settings.defaultCurrency.trim().toUpperCase();
    return (
      source: source,
      startFee: settingsUsable ? base : _fallbackStartFee,
      perKm: settingsUsable ? perKm : _fallbackPerKm,
      waitPerMin: settingsUsable ? wait : _fallbackWaitPerMin,
      vatRate: vatRate,
      vatMode: vatMode,
      currency: currency,
    );
  }

  double _directRideCustomerTotalFromRaw(double rawTotal) {
    final pricing = _resolveDirectRidePricing();
    if (pricing.vatMode == 'excl') {
      return rawTotal * (1.0 + pricing.vatRate);
    }
    return rawTotal;
  }

  Map<String, dynamic> _directRidePricingSnapshotPayload() {
    final pricing = _resolveDirectRidePricing();
    debugPrint(
      '[DIRECT_RIDE][PRICING_SNAPSHOT] source=${pricing.source} '
      'base=${pricing.startFee.toStringAsFixed(2)} '
      'perKm=${pricing.perKm.toStringAsFixed(2)} '
      'wait=${pricing.waitPerMin.toStringAsFixed(4)} '
      'vatRate=${pricing.vatRate.toStringAsFixed(4)} '
      'vatMode=${pricing.vatMode}',
    );
    return <String, dynamic>{
      'start_fee': pricing.startFee,
      'per_km': pricing.perKm,
      'wait_per_min': pricing.waitPerMin,
      'vat_rate': pricing.vatRate,
      'vat_mode': pricing.vatMode,
      'currency': pricing.currency,
    };
  }

  double get _liveMeterTotalEur {
    final km = _kmDriven;
    final waitMin = _effectiveWaitElapsed.inMilliseconds / 60000.0;
    final pricing = _resolveDirectRidePricing();
    final raw =
        pricing.startFee +
        (km * pricing.perKm) +
        (waitMin * pricing.waitPerMin);
    return _directRideCustomerTotalFromRaw(raw);
  }

  void _debugLiveMeter({required String reason}) {
    final now = DateTime.now();
    final last = _lastMeterDebugAt;
    if (last != null && now.difference(last).inSeconds < 5) return;
    _lastMeterDebugAt = now;
    final waitMin = _effectiveWaitElapsed.inMilliseconds / 60000.0;
    final pricing = _resolveDirectRidePricing();
    final kmCost = _kmDriven * pricing.perKm;
    final waitCost = waitMin * pricing.waitPerMin;
    final raw = pricing.startFee + kmCost + waitCost;
    final total = _directRideCustomerTotalFromRaw(raw);
    debugPrint(
      '[METER][$reason] waiting=$_isWaiting km=${_kmDriven.toStringAsFixed(3)} kmCost=${kmCost.toStringAsFixed(2)} waitSec=${_effectiveWaitElapsed.inSeconds} waitCost=${waitCost.toStringAsFixed(2)} total=${total.toStringAsFixed(2)}',
    );
  }

  /// Price text shown in the cockpit:
  /// - Booking selected: show fixed price if known, otherwise "€ —" (never show live meter for bookings)
  /// - No booking selected: show the live meter total
  String get _displayTotalText {
    if (_liveRideActive) {
      final live = _liveMeterTotalEur;
      return '€ ${live.toStringAsFixed(2)}';
    }
    final fixed = _fixedBookingPriceEur;
    if (_activeBooking != null) {
      if (fixed != null && fixed > 0) return '€ ${fixed.toStringAsFixed(2)}';
      return '€ —';
    }
    final live = _liveMeterTotalEur;
    return '€ ${live.toStringAsFixed(2)}';
  }

  String get _cockpitPriceText =>
      _displayTotalText.replaceFirst('€', '').trim();

  String _formatDirectRideEstimateText(double amount, String currency) {
    final normalizedCurrency = currency.trim().isEmpty
        ? kDefaultCurrency
        : currency.trim().toUpperCase();
    if (normalizedCurrency == 'EUR') {
      return '€ ${amount.toStringAsFixed(2)}';
    }
    return '$normalizedCurrency ${amount.toStringAsFixed(2)}';
  }

  double? _quoteNumber(dynamic value) {
    if (value is num) {
      final v = value.toDouble();
      return v.isFinite ? v : null;
    }
    if (value is String) {
      var s = value.trim();
      if (s.isEmpty) return null;
      s = s.replaceAll(RegExp(r'[^0-9,\.\-]'), '');
      if (s.contains(',') && !s.contains('.')) s = s.replaceAll(',', '.');
      if (s.contains(',') && s.contains('.')) s = s.replaceAll(',', '');
      final parsed = double.tryParse(s);
      if (parsed == null || !parsed.isFinite) return null;
      return parsed;
    }
    return null;
  }

  String _directRideEstimateCurrencyFrom(dynamic data) {
    if (data is! Map) return kDefaultCurrency;
    final map = Map<String, dynamic>.from(data);
    final direct = map['currency']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct.toUpperCase();
    final quote = map['quote'];
    if (quote is Map) {
      final nested = quote['currency']?.toString().trim();
      if (nested != null && nested.isNotEmpty) return nested.toUpperCase();
      final pricing = quote['pricing'];
      if (pricing is Map) {
        final pricingCurrency = pricing['currency']?.toString().trim();
        if (pricingCurrency != null && pricingCurrency.isNotEmpty) {
          return pricingCurrency.toUpperCase();
        }
      }
    }
    final pricing = map['pricing'];
    if (pricing is Map) {
      final pricingCurrency = pricing['currency']?.toString().trim();
      if (pricingCurrency != null && pricingCurrency.isNotEmpty) {
        return pricingCurrency.toUpperCase();
      }
    }
    return kDefaultCurrency;
  }

  ({double? amount, String? source}) _extractQuoteEstimateResult(dynamic data) {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    final root = asMap(data);
    final quote = asMap(root['quote']);
    final pricing = asMap(root['pricing']);
    final quotePricing = asMap(quote['pricing']);
    final quotePricingMain = asMap(
      quote['pricing_main'] ?? quote['pricingMain'],
    );
    final pricingMain = asMap(root['pricing_main'] ?? root['pricingMain']);
    final candidates = <({String source, dynamic value})>[
      (
        source: 'root.total_price_incl_vat',
        value: root['total_price_incl_vat'],
      ),
      (source: 'root.price_incl_vat', value: root['price_incl_vat']),
      (source: 'root.total_price', value: root['total_price']),
      (source: 'root.total', value: root['total']),
      (source: 'root.price', value: root['price']),
      (source: 'root.amount', value: root['amount']),
      (source: 'root.eur', value: root['eur']),
      (
        source: 'quote.total_price_incl_vat',
        value: quote['total_price_incl_vat'],
      ),
      (source: 'quote.price_incl_vat', value: quote['price_incl_vat']),
      (source: 'quote.total_price', value: quote['total_price']),
      (source: 'quote.total', value: quote['total']),
      (source: 'quote.price', value: quote['price']),
      (source: 'quote.amount', value: quote['amount']),
      (source: 'quote.eur', value: quote['eur']),
      (source: 'pricing.price_incl_vat', value: pricing['price_incl_vat']),
      (source: 'pricing.total_price', value: pricing['total_price']),
      (source: 'pricing.total', value: pricing['total']),
      (source: 'pricing.price', value: pricing['price']),
      (source: 'pricing.amount', value: pricing['amount']),
      (source: 'pricing.eur', value: pricing['eur']),
      (
        source: 'quote.pricing.price_incl_vat',
        value: quotePricing['price_incl_vat'],
      ),
      (source: 'quote.pricing.total_price', value: quotePricing['total_price']),
      (source: 'quote.pricing.total', value: quotePricing['total']),
      (source: 'quote.pricing.price', value: quotePricing['price']),
      (source: 'quote.pricing.amount', value: quotePricing['amount']),
      (source: 'quote.pricing.eur', value: quotePricing['eur']),
      (
        source: 'quote.pricing_main.price_incl_vat',
        value: quotePricingMain['price_incl_vat'],
      ),
      (
        source: 'pricing_main.price_incl_vat',
        value: pricingMain['price_incl_vat'],
      ),
    ];
    for (final candidate in candidates) {
      final parsed = _quoteNumber(candidate.value);
      if (parsed != null) {
        return (amount: parsed, source: candidate.source);
      }
    }
    return (amount: null, source: null);
  }

  double? _extractQuoteEstimateTotal(dynamic data) {
    return _extractQuoteEstimateResult(data).amount;
  }

  String _estimateMapKeys(dynamic value) {
    if (value is! Map) return '-';
    final keys = value.keys.map((k) => k.toString()).toList(growable: false);
    if (keys.isEmpty) return '-';
    if (keys.length <= 10) return keys.join(',');
    return '${keys.take(10).join(',')},...';
  }

  void _scheduleDirectRideLocationRetry({required String reason}) {
    _directRideEstimateLocationRetryTimer?.cancel();
    final destination = (_directRideDestinationText ?? '').trim();
    if (!_directRideDraft || destination.isEmpty) {
      return;
    }
    if (_directRideLocationRetryCount >= _maxDirectRideLocationRetries) {
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][RETRY_SKIP] reason=$reason retries=$_directRideLocationRetryCount max=$_maxDirectRideLocationRetries',
      );
      return;
    }
    _directRideLocationRetryCount += 1;
    final retryAttempt = _directRideLocationRetryCount;
    debugPrint(
      '[DIRECT_RIDE][ESTIMATE][RETRY_SCHEDULE] reason=$reason attempt=$retryAttempt delay_ms=1800',
    );
    _directRideEstimateLocationRetryTimer = Timer(
      const Duration(milliseconds: 1800),
      () {
        if (!mounted) return;
        final latestDestination = (_directRideDestinationText ?? '').trim();
        if (!_directRideDraft || latestDestination.isEmpty) return;
        unawaited(
          _refreshDirectRideEstimate(reason: 'location_retry_$retryAttempt'),
        );
      },
    );
  }

  void _scheduleDirectRideEstimateRefresh({required String reason}) {
    if (!_directRideDraft) {
      _directRideEstimateDebounce?.cancel();
      _directRideEstimateLocationRetryTimer?.cancel();
      return;
    }
    final destination = (_directRideDestinationText ?? '').trim();
    if (_directRideLocationRetryDestination != destination) {
      _directRideLocationRetryDestination = destination;
      _directRideLocationRetryCount = 0;
      _directRideEstimateLocationRetryTimer?.cancel();
    }
    if (destination.isEmpty) {
      _directRideEstimateDebounce?.cancel();
      _directRideEstimateLocationRetryTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _directRideEstimatedFare = null;
        _directRideEstimateLoading = false;
        _directRideEstimateError = null;
        _directRideEstimateCurrency = kDefaultCurrency;
        _directRideEstimateSignature = null;
        _directRideLocationRetryCount = 0;
        _directRideLocationRetryDestination = null;
      });
      return;
    }
    _directRideEstimateDebounce?.cancel();
    _directRideEstimateDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_refreshDirectRideEstimate(reason: reason));
    });
  }

  Future<({geo.Position? position, String source, String? failureReason})>
  _resolveDirectRideEstimateOriginPosition({required String reason}) async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    var permission = await geo.Geolocator.checkPermission();
    debugPrint(
      '[DIRECT_RIDE][ESTIMATE][LOCATION_STATUS] reason=$reason serviceEnabled=$serviceEnabled permission=${permission.name} source=resolver',
    );

    final cached = _lastPos;
    if (cached != null) {
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][POSITION_RESOLVED] reason=$reason source=lastPos',
      );
      return (position: cached, source: 'lastPos', failureReason: null);
    }

    if (!serviceEnabled) {
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][POSITION_FAILED] reason=service_disabled source=resolver',
      );
      return (
        position: null,
        source: 'none',
        failureReason: 'service_disabled',
      );
    }

    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][LOCATION_STATUS] reason=$reason serviceEnabled=$serviceEnabled permission=${permission.name} source=request',
      );
    }

    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][POSITION_FAILED] reason=permission_denied source=resolver',
      );
      return (
        position: null,
        source: 'none',
        failureReason: 'permission_denied',
      );
    }

    try {
      final lastKnown = await geo.Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _lastPos = lastKnown;
        debugPrint(
          '[DIRECT_RIDE][ESTIMATE][POSITION_RESOLVED] reason=$reason source=lastKnown',
        );
        return (position: lastKnown, source: 'lastKnown', failureReason: null);
      }
    } catch (e) {
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][POSITION_FAILED] reason=exception source=lastKnown error=$e',
      );
    }

    try {
      final current = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      ).timeout(const Duration(seconds: 8));
      _lastPos = current;
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][POSITION_RESOLVED] reason=$reason source=current',
      );
      return (position: current, source: 'current', failureReason: null);
    } on TimeoutException {
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][POSITION_FAILED] reason=timeout source=current',
      );
      return (position: null, source: 'none', failureReason: 'timeout');
    } catch (e) {
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][POSITION_FAILED] reason=exception source=current error=$e',
      );
      return (position: null, source: 'none', failureReason: 'exception');
    }
  }

  Future<void> _refreshDirectRideEstimate({required String reason}) async {
    final destination = (_directRideDestinationText ?? '').trim();
    final shouldEstimate = _directRideDraft;
    debugPrint(
      '[DIRECT_RIDE][ESTIMATE][START] reason=$reason hasDestination=${destination.isNotEmpty} hasLastPos=${_lastPos != null} isDraft=$shouldEstimate',
    );
    if (!shouldEstimate || destination.isEmpty) return;

    final resolvedPosition = await _resolveDirectRideEstimateOriginPosition(
      reason: reason,
    );
    final pos = resolvedPosition.position;

    if (pos == null) {
      if (!mounted) return;
      setState(() {
        _directRideEstimateLoading = false;
        _directRideEstimateError = 'location_unavailable';
      });
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][WARN] reason=$reason hasPosition=false failure=${resolvedPosition.failureReason ?? 'unknown'} error=location_unavailable',
      );
      if (resolvedPosition.failureReason != 'permission_denied' &&
          resolvedPosition.failureReason != 'service_disabled') {
        _scheduleDirectRideLocationRetry(reason: reason);
      }
      return;
    }

    final pickupText =
        '${pos.longitude.toStringAsFixed(6)},${pos.latitude.toStringAsFixed(6)}';
    final signature =
        '$pickupText|$destination|${_routeKm?.toStringAsFixed(3) ?? '-'}|${_routeDurationSec ?? -1}';
    if (!_directRideEstimateLoading &&
        _directRideEstimateSignature == signature &&
        _directRideEstimatedFare != null) {
      return;
    }

    final requestSeq = ++_directRideEstimateRequestSeq;
    if (mounted) {
      setState(() {
        _directRideEstimateLoading = true;
        _directRideEstimateError = null;
      });
    }

    final settings = businessSettingsNotifier.value;
    final vat = localBackendTaxProfileNotifier.value;
    final vatRateBase = vat?.vatRate ?? settings.pricingVatRate;
    final vatRate =
        (vatRateBase.isFinite ? vatRateBase : settings.pricingVatRate)
            .clamp(0.0, 1.0)
            .toDouble();
    final vatMode = (vat?.vatDisplayMode ?? 'incl').trim().isEmpty
        ? 'incl'
        : (vat?.vatDisplayMode ?? 'incl').trim();
    final scope = _activeBookingScopeQuery();
    final hasStrictScope = _strictActiveBookingScopeQuery() != null;
    debugPrint(
      '[DIRECT_RIDE][ESTIMATE][CONTEXT] reason=$reason hasPosition=true hasScope=${scope.isNotEmpty} hasStrictScope=$hasStrictScope tenant=${scope['tenant_id'] ?? '-'} company=${scope['company_id'] ?? '-'}',
    );
    final pickupAt = DateTime.now().add(const Duration(minutes: 5));
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${pickupAt.year}-${two(pickupAt.month)}-${two(pickupAt.day)}';
    final time = '${two(pickupAt.hour)}:${two(pickupAt.minute)}';
    final pickupIso = '${date}T$time:00';
    final bookingCurrency = normalizeExplicitIsoCurrencyCode(
      settings.defaultCurrency,
    );

    final body = <String, dynamic>{
      'from': pickupText,
      'to': destination,
      'date': date,
      'time': time,
      'pickup_iso': pickupIso,
      'tier': 'COMFORT',
      'service': 'AIRPORT',
      'pax': 1,
      'bags': 0,
      'wait_min': 0,
      'return': false,
      'return_enabled': false,
      'return_from': '',
      'return_to': '',
      'return_date': '',
      'return_time': '',
      'return_pickup_iso': '',
      'vat_rate': vatRate,
      'vat_mode': vatMode,
      if (bookingCurrency.isNotEmpty) 'currency': bookingCurrency,
      'pricing_profile': <String, dynamic>{
        'base_fare': settings.pricingBaseFare,
        'price_per_km': settings.pricingPerKm,
        'price_per_minute': settings.pricingPerMinute,
        'minimum_fare': settings.pricingMinimumFare,
        'wait_per_minute': settings.pricingWaitPerMinute,
        'return_enabled': settings.pricingReturnEnabled,
        'return_fee': settings.pricingReturnFee,
        'fuel_surcharge': settings.pricingFuelSurcharge,
        'vat_rate': vatRate,
        'vat_mode': vatMode,
        if (bookingCurrency.isNotEmpty) 'currency': bookingCurrency,
      },
      'surcharge_fuel': settings.pricingFuelSurcharge,
      'return_fee': 0,
      'extra_service': 'NONE',
      'extra_service_key': 'NONE',
      ...scope,
    };

    try {
      final uri = _withActiveBookingScope(kBookingBaseUrl, '/quote');
      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final bodySnippet = res.body
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .replaceAll(RegExp(r'[\r\n\t]'), ' ');
        final safeSnippet = bodySnippet.length > 280
            ? '${bodySnippet.substring(0, 280)}...'
            : bodySnippet;
        throw Exception(
          'quote_http_${res.statusCode}${safeSnippet.isNotEmpty ? ': $safeSnippet' : ''}',
        );
      }
      final decoded = jsonDecode(res.body);
      final estimateResult = _extractQuoteEstimateResult(decoded);
      final estimate = estimateResult.amount;
      if (estimate == null) {
        if (decoded is Map) {
          final root = Map<String, dynamic>.from(decoded);
          final quote = root['quote'];
          final pricing = root['pricing'];
          final quotePricing = quote is Map ? quote['pricing'] : null;
          debugPrint(
            '[DIRECT_RIDE][ESTIMATE][PARSE_MISS] reason=$reason rootKeys=${_estimateMapKeys(root)} quoteKeys=${_estimateMapKeys(quote)} pricingKeys=${_estimateMapKeys(pricing)} quotePricingKeys=${_estimateMapKeys(quotePricing)}',
          );
        }
        throw Exception('quote_total_missing');
      }
      if (!mounted || requestSeq != _directRideEstimateRequestSeq) return;
      setState(() {
        _directRideEstimatedFare = estimate;
        _directRideEstimateCurrency = _directRideEstimateCurrencyFrom(decoded);
        _directRideEstimateLoading = false;
        _directRideEstimateError = null;
        _directRideEstimateSignature = signature;
        _directRideLocationRetryCount = 0;
      });
      debugPrint(
        '[DIRECT_RIDE][ESTIMATE][OK] reason=$reason amount=${estimate.toStringAsFixed(2)} source=${estimateResult.source ?? 'unknown'}',
      );
    } catch (e) {
      if (!mounted || requestSeq != _directRideEstimateRequestSeq) return;
      final errorText = e.toString();
      final safeError = errorText.contains('quote_total_missing')
          ? 'quote_total_missing'
          : errorText;
      setState(() {
        _directRideEstimateLoading = false;
        _directRideEstimateError = safeError;
      });
      debugPrint('[DIRECT_RIDE][ESTIMATE][WARN] reason=$reason error=$e');
    }
  }

  Future<void> _sendDirectTripWaitEvent({
    required String path,
    required String logLabel,
    required String timestampKey,
  }) async {
    final tripId = _activeDirectTripId;
    if (!_directRideActive || tripId == null || tripId.trim().isEmpty) return;
    try {
      final strictScope = _strictBookingScopeForMutation(
        action: 'direct_trip_wait_event_$logLabel',
        showUx: false,
      );
      if (strictScope == null) return;
      final payload = <String, dynamic>{
        'trip_id': tripId,
        ...strictScope,
        timestampKey: DateTime.now().toUtc().toIso8601String(),
      };
      final res = await http
          .post(
            _uriWithScope(kWorkerBaseUrl, path, strictScope),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      debugPrint('[DIRECT_TRIP][$logLabel][OK] trip_id=$tripId');
    } catch (e) {
      debugPrint('[DIRECT_TRIP][$logLabel][WARN] local wait only: $e');
    }
  }

  String _directRideVehicleId() {
    final activeCompanyId =
        companyProfileNotifier.value?.companyId.trim().isNotEmpty == true
        ? companyProfileNotifier.value!.companyId.trim()
        : (activeCompanySessionNotifier.value?.companyId.trim().isNotEmpty ==
                  true
              ? activeCompanySessionNotifier.value!.companyId.trim()
              : '');
    final activeDriverId = kDriverId.trim();
    final candidateVehicles = activeCompanyId.isNotEmpty
        // Company-scoped fallback prevents cross-company vehicle reuse in direct rides.
        ? vehiclesNotifier.value
              .where(
                (vehicle) =>
                    (vehicle.companyId?.trim() ?? '') == activeCompanyId,
              )
              .toList(growable: false)
        : vehiclesNotifier.value;

    for (final vehicle in candidateVehicles) {
      if (vehicle.isActive &&
          vehicle.driverId == activeDriverId &&
          vehicle.id.trim().isNotEmpty) {
        return vehicle.id.trim();
      }
    }
    for (final vehicle in candidateVehicles) {
      if (vehicle.isActive && vehicle.id.trim().isNotEmpty) {
        return vehicle.id.trim();
      }
    }
    if (candidateVehicles.isNotEmpty) {
      final firstId = candidateVehicles.first.id.trim();
      if (firstId.isNotEmpty) return firstId;
    }
    if (activeCompanyId.isNotEmpty) return '';
    return 'vh_1';
  }

  Map<String, dynamic> _currentOriginPayload(geo.Position? pos) {
    if (pos == null) {
      return <String, dynamic>{'label': _receiptText('currentLocation')};
    }
    return <String, dynamic>{
      'label':
          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}',
      'lat': pos.latitude,
      'lon': pos.longitude,
    };
  }

  Map<String, dynamic> _plannedBookingDetailsPayload(BookingItem booking) {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    List<dynamic> asList(dynamic value) => value is List ? value : const [];
    String? text(dynamic value) {
      final s = value?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    num? number(dynamic value) {
      if (value is num) return value;
      if (value is String) return num.tryParse(value.replaceAll(',', '.'));
      return null;
    }

    dynamic pick(List<List<String>> paths) {
      for (final path in paths) {
        dynamic current = booking.details;
        for (final key in path) {
          if (current is Map && current.containsKey(key)) {
            current = current[key];
          } else {
            current = null;
            break;
          }
        }
        if (current != null) return current;
      }
      return null;
    }

    final bookingMap = asMap(booking.details['booking']);
    final detailMap = booking.details;
    final quote = asMap(booking.details['quote']);
    final record = asMap(booking.details['record']);
    final recordQuote = asMap(record['quote']);
    final recordPayload = asMap(record['payload']);
    final payloadQuote = asMap(recordPayload['quote']);
    if (quote.isEmpty && recordQuote.isNotEmpty) {
      quote.addAll(recordQuote);
    }
    if (quote.isEmpty && payloadQuote.isNotEmpty) {
      quote.addAll(payloadQuote);
    }
    final inputs = asMap(quote['inputs']);
    final pricing = asMap(quote['pricing']);
    final pricingMain = asMap(quote['pricing_main'] ?? quote['pricingMain']);
    final pricingReturn = asMap(
      quote['pricing_return'] ?? quote['pricingReturn'],
    );
    final returnInfo = asMap(quote['return']);
    final tracking = asMap(booking.details['tracking_booking']);
    final payload = recordPayload;
    final customer = asMap(payload['customer']);
    final bookingCustomer = asMap(bookingMap['customer']);
    final payloadBooking = asMap(payload['booking']);
    final payloadBookingCustomer = asMap(payloadBooking['customer']);
    final customerName = text(
      bookingMap['custName'] ??
          bookingMap['customer_name'] ??
          bookingMap['customerName'] ??
          bookingMap['name'] ??
          bookingCustomer['name'] ??
          bookingCustomer['full_name'] ??
          detailMap['customer_name'] ??
          detailMap['customerName'] ??
          detailMap['name'] ??
          payload['name'] ??
          payload['customer_name'] ??
          payload['customerName'] ??
          payloadBooking['customer_name'] ??
          payloadBooking['customerName'] ??
          payloadBooking['name'] ??
          payloadBookingCustomer['name'] ??
          payloadBookingCustomer['full_name'] ??
          customer['name'] ??
          customer['full_name'] ??
          pick([
            ['customer', 'name'],
            ['booking', 'customer', 'name'],
            ['record', 'payload', 'customer', 'name'],
            ['record', 'payload', 'booking', 'customer', 'name'],
          ]),
    );
    final customerPhone = text(
      bookingMap['custPhone'] ??
          bookingMap['customer_phone'] ??
          bookingMap['customerPhone'] ??
          bookingMap['phone'] ??
          bookingMap['tel'] ??
          bookingMap['mobile'] ??
          bookingCustomer['phone'] ??
          bookingCustomer['tel'] ??
          bookingCustomer['mobile'] ??
          detailMap['customer_phone'] ??
          detailMap['customerPhone'] ??
          detailMap['phone'] ??
          detailMap['tel'] ??
          detailMap['mobile'] ??
          payload['phone'] ??
          payload['customer_phone'] ??
          payload['customerPhone'] ??
          payload['tel'] ??
          payload['mobile'] ??
          payloadBooking['customer_phone'] ??
          payloadBooking['customerPhone'] ??
          payloadBooking['phone'] ??
          payloadBooking['tel'] ??
          payloadBooking['mobile'] ??
          payloadBookingCustomer['phone'] ??
          payloadBookingCustomer['tel'] ??
          payloadBookingCustomer['mobile'] ??
          customer['phone'] ??
          customer['tel'] ??
          customer['mobile'] ??
          pick([
            ['customer', 'phone'],
            ['booking', 'customer', 'phone'],
            ['record', 'payload', 'customer', 'phone'],
            ['record', 'payload', 'booking', 'customer', 'phone'],
          ]),
    );
    final customerEmail = text(
      bookingMap['custEmail'] ??
          bookingMap['customer_email'] ??
          bookingMap['customerEmail'] ??
          bookingMap['email'] ??
          bookingCustomer['email'] ??
          detailMap['customer_email'] ??
          detailMap['customerEmail'] ??
          detailMap['email'] ??
          payload['email'] ??
          payload['customer_email'] ??
          payload['customerEmail'] ??
          payloadBooking['customer_email'] ??
          payloadBooking['customerEmail'] ??
          payloadBooking['email'] ??
          payloadBookingCustomer['email'] ??
          customer['email'] ??
          pick([
            ['customer', 'email'],
            ['booking', 'customer', 'email'],
            ['record', 'payload', 'customer', 'email'],
            ['record', 'payload', 'booking', 'customer', 'email'],
          ]),
    );
    final customerCountry = text(
      bookingMap['customer_country'] ??
          bookingMap['customerCountry'] ??
          bookingMap['country'] ??
          bookingMap['countryCode'] ??
          bookingMap['country_iso'] ??
          bookingMap['countryIso'] ??
          detailMap['customer_country'] ??
          detailMap['customerCountry'] ??
          detailMap['country'] ??
          detailMap['countryCode'] ??
          detailMap['country_iso'] ??
          detailMap['countryIso'] ??
          payload['customer_country'] ??
          payload['customerCountry'] ??
          payload['country'] ??
          payload['countryCode'] ??
          payload['country_iso'] ??
          payload['countryIso'] ??
          payload['locale'] ??
          payload['language'] ??
          customer['country'] ??
          customer['countryCode'] ??
          customer['countryIso'],
    );
    final phoneCountryCode = text(
      bookingMap['phone_country_code'] ??
          bookingMap['phoneCountryCode'] ??
          detailMap['phone_country_code'] ??
          detailMap['phoneCountryCode'] ??
          payload['phone_country_code'] ??
          payload['phoneCountryCode'] ??
          customer['phone_country_code'] ??
          customer['phoneCountryCode'],
    );
    final dialCode = text(
      bookingMap['dial_code'] ??
          bookingMap['dialCode'] ??
          detailMap['dial_code'] ??
          detailMap['dialCode'] ??
          payload['dial_code'] ??
          payload['dialCode'] ??
          customer['dial_code'] ??
          customer['dialCode'],
    );

    final pickupAddress =
        text(booking.from) ??
        text(quote['from']) ??
        text(inputs['from']) ??
        text(bookingMap['from']) ??
        text(tracking['pickup']);
    final destinationAddress =
        text(booking.to) ??
        text(quote['to']) ??
        text(inputs['to']) ??
        text(bookingMap['to']) ??
        text(tracking['dropoff']);
    String? normalizeServiceToken(String? raw) {
      final token = raw?.trim();
      if (token == null || token.isEmpty) return null;
      final normalized = token
          .toLowerCase()
          .replaceAll('-', '_')
          .replaceAll(' ', '_');
      if (normalized == 'airport' ||
          normalized == 'airport_transfer' ||
          normalized == 'luchthaven') {
        return 'airport';
      }
      if (normalized == 'business' || normalized == 'zakelijk') {
        return 'business';
      }
      if (normalized == 'passenger' ||
          normalized == 'passenger_transport' ||
          normalized == 'personenvervoer') {
        return 'passenger';
      }
      return normalized;
    }

    String? normalizeTierToken(String? raw) {
      final token = raw?.trim();
      if (token == null || token.isEmpty) return null;
      final normalized = token
          .toLowerCase()
          .replaceAll('-', '_')
          .replaceAll(' ', '_');
      if (normalized == 'comfort' ||
          normalized == 'private' ||
          normalized == 'premium') {
        return normalized;
      }
      return normalized;
    }

    final service = normalizeServiceToken(
      text(
        bookingMap['service_type'] ??
            bookingMap['serviceType'] ??
            bookingMap['service'] ??
            detailMap['service_type'] ??
            detailMap['serviceType'] ??
            detailMap['service'] ??
            payload['service_type'] ??
            payload['serviceType'] ??
            payload['service'] ??
            inputs['service_type'] ??
            inputs['serviceType'] ??
            inputs['service'] ??
            pick([
              ['service_type'],
              ['serviceType'],
              ['service'],
            ]),
      ),
    );
    final tier = normalizeTierToken(
      text(
        booking.tier ??
            bookingMap['tier'] ??
            bookingMap['vehicle_tier'] ??
            bookingMap['vehicleTier'] ??
            detailMap['tier'] ??
            detailMap['vehicle_tier'] ??
            detailMap['vehicleTier'] ??
            payload['tier'] ??
            payload['vehicle_tier'] ??
            payload['vehicleTier'] ??
            inputs['tier'] ??
            inputs['vehicle_tier'] ??
            inputs['vehicleTier'],
      ),
    );
    final scheduledPickup =
        text(booking.pickupIso) ??
        text(bookingMap['pickupStartIso']) ??
        text(bookingMap['pickup_iso']) ??
        text(inputs['pickup_iso']);
    final totalPackage =
        number(bookingMap['price_incl_vat']) ??
        number(pricing['price_incl_vat']) ??
        number(pricing['total_price_incl_vat']) ??
        number(quote['total_price_incl_vat']) ??
        number(quote['price_incl_vat']) ??
        booking.price;
    final operationalLeg = booking.isOperationalLeg;
    final legTypeToken = operationalLeg
        ? _operationalLegTypeToken(booking)
        : null;
    final segmentPrice = operationalLeg
        ? _driverDisplayPriceForBooking(booking)
        : (booking.bookingId.endsWith('-R')
              ? (number(bookingMap['price_incl_vat_return']) ??
                    number(pricingReturn['price_incl_vat']) ??
                    number(returnInfo['price_incl_vat']) ??
                    number(asMap(returnInfo['pricing'])['price_incl_vat']))
              : (number(bookingMap['price_incl_vat_main']) ??
                    number(pricingMain['price_incl_vat']) ??
                    number(quote['price_incl_vat'])));
    final returnPickup =
        text(bookingMap['returnPickupIso']) ??
        text(inputs['return_pickup_iso']) ??
        text(
          pick([
            ['return_pickup_iso'],
          ]),
        );
    final returnFrom =
        text(bookingMap['return_from']) ??
        text(inputs['return_from']) ??
        text(returnInfo['from']);
    final returnTo =
        text(bookingMap['return_to']) ??
        text(inputs['return_to']) ??
        text(returnInfo['to']);
    final hasReturnInfo =
        returnPickup != null ||
        returnFrom != null ||
        returnTo != null ||
        returnInfo['enabled'] == true ||
        pricingReturn.isNotEmpty;
    final paymentStatus = text(
      bookingMap['payment_status'] ??
          bookingMap['paymentStatus'] ??
          detailMap['payment_status'] ??
          detailMap['paymentStatus'] ??
          payload['payment_status'] ??
          payload['paymentStatus'] ??
          pick([
            ['payment_status'],
            ['paymentStatus'],
            ['booking', 'payment_status'],
            ['booking', 'paymentStatus'],
          ]),
    );
    final paidAt = text(
      bookingMap['paid_at'] ??
          bookingMap['paidAt'] ??
          detailMap['paid_at'] ??
          detailMap['paidAt'] ??
          payload['paid_at'] ??
          payload['paidAt'],
    );
    final paymentProvider = text(
      bookingMap['payment_provider'] ??
          bookingMap['paymentProvider'] ??
          detailMap['payment_provider'] ??
          detailMap['paymentProvider'] ??
          payload['payment_provider'] ??
          payload['paymentProvider'],
    );
    final paymentId = text(
      bookingMap['payment_id'] ??
          bookingMap['paymentId'] ??
          detailMap['payment_id'] ??
          detailMap['paymentId'] ??
          payload['payment_id'] ??
          payload['paymentId'],
    );

    List<Map<String, dynamic>> normalizeSegments(dynamic raw) {
      final result = <Map<String, dynamic>>[];
      for (final value in asList(raw)) {
        if (value is! Map) continue;
        final segment = Map<String, dynamic>.from(value);
        final from = text(
          segment['from'] ??
              segment['origin'] ??
              segment['start'] ??
              segment['start_address'],
        );
        final to = text(
          segment['to'] ??
              segment['destination'] ??
              segment['end'] ??
              segment['end_address'],
        );
        result.add(<String, dynamic>{
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          if (number(segment['distance_km'] ?? segment['km']) != null)
            'distance_km': number(segment['distance_km'] ?? segment['km']),
          if (number(segment['duration_min'] ?? segment['minutes']) != null)
            'duration_min': number(
              segment['duration_min'] ?? segment['minutes'],
            ),
        });
      }
      return result;
    }

    final routeSegments = normalizeSegments(
      quote['route_segments'] ??
          quote['legs'] ??
          bookingMap['route_segments'] ??
          bookingMap['legs'],
    );
    if (routeSegments.isEmpty &&
        pickupAddress != null &&
        destinationAddress != null) {
      final distance = number(
        quote['distance_km'] ?? bookingMap['distance_km'],
      );
      final duration = number(
        quote['duration_min'] ?? bookingMap['duration_route_min'],
      );
      if (distance != null || duration != null) {
        routeSegments.add(<String, dynamic>{
          'from': pickupAddress,
          'to': destinationAddress,
          if (distance != null) 'distance_km': distance,
          if (duration != null) 'duration_min': duration,
        });
      }
    }
    if (hasReturnInfo) {
      final returnDistance = number(
        returnInfo['distance_km'] ?? bookingMap['return_distance_km'],
      );
      final returnDuration = number(
        returnInfo['duration_min'] ?? bookingMap['return_duration_min'],
      );
      if (returnFrom != null ||
          returnTo != null ||
          returnDistance != null ||
          returnDuration != null) {
        routeSegments.add(<String, dynamic>{
          if (returnFrom != null) 'from': returnFrom,
          if (returnTo != null) 'to': returnTo,
          if (returnDistance != null) 'distance_km': returnDistance,
          if (returnDuration != null) 'duration_min': returnDuration,
          'kind': 'return',
        });
      }
    }
    final refMaps = _referenceLookupMaps(<Map<String, dynamic>>[
      detailMap,
      bookingMap,
      payload,
      quote,
      record,
      recordPayload,
      payloadBooking,
    ]);
    final refs = _extractBusinessReferenceAliasesFromMaps(refMaps);

    return <String, dynamic>{
      if (pickupAddress != null) 'pickup_address': pickupAddress,
      if (destinationAddress != null) 'destination_address': destinationAddress,
      if (scheduledPickup != null) 'scheduled_pickup_at': scheduledPickup,
      if (operationalLeg && legTypeToken == 'return') 'subtype': 'Retourrit',
      if (operationalLeg && legTypeToken == 'outbound') 'subtype': 'Heenrit',
      if (!operationalLeg && booking.bookingId.endsWith('-R'))
        'subtype': 'Retourrit',
      if (!operationalLeg && !booking.bookingId.endsWith('-R') && hasReturnInfo)
        'subtype': 'Heenrit',
      if (operationalLeg && booking.legId.trim().isNotEmpty) ...{
        'leg_id': booking.legId.trim(),
        'legId': booking.legId.trim(),
        'is_operational_leg': true,
        'isOperationalLeg': true,
      },
      if (operationalLeg && legTypeToken != null) ...{
        'leg_type': legTypeToken,
        'legType': legTypeToken,
      },
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      if (customerEmail != null) 'customer_email': customerEmail,
      if (customerName != null ||
          customerPhone != null ||
          customerEmail != null)
        'customer': <String, dynamic>{
          if (customerName != null) 'name': customerName,
          if (customerPhone != null) 'phone': customerPhone,
          if (customerEmail != null) 'email': customerEmail,
        },
      if (customerCountry != null) 'customer_country': customerCountry,
      if (phoneCountryCode != null) 'phone_country_code': phoneCountryCode,
      if (dialCode != null) 'dial_code': dialCode,
      if (service != null) ...{
        'service_type': service,
        'serviceType': service,
        'service': service,
      },
      if (tier != null) ...{
        'tier': tier,
        'vehicle_tier': tier,
        'vehicleTier': tier,
      },
      if (number(booking.pax ?? bookingMap['pax'] ?? inputs['pax']) != null)
        'passengers': number(booking.pax ?? bookingMap['pax'] ?? inputs['pax']),
      if (number(booking.bags ?? bookingMap['bags'] ?? inputs['bags']) != null)
        'luggage_count': number(
          booking.bags ?? bookingMap['bags'] ?? inputs['bags'],
        ),
      if (number(bookingMap['wait_min'] ?? inputs['wait_min']) != null)
        'booked_wait_minutes': number(
          bookingMap['wait_min'] ?? inputs['wait_min'],
        ),
      if ((booking.status ?? '').trim().isNotEmpty)
        'booking_status': booking.status!.trim(),
      if (paymentStatus != null) ...{
        'payment_status': paymentStatus,
        'paymentStatus': paymentStatus,
      },
      if (paidAt != null) ...{'paid_at': paidAt, 'paidAt': paidAt},
      if (paymentProvider != null) ...{
        'payment_provider': paymentProvider,
        'paymentProvider': paymentProvider,
      },
      if (paymentId != null) ...{
        'payment_id': paymentId,
        'paymentId': paymentId,
      },
      if (refs.receipt != null) ...{
        'receipt_reference': refs.receipt,
        'receiptReference': refs.receipt,
      },
      if (refs.planning != null) ...{
        'planning_reference': refs.planning,
        'planningReference': refs.planning,
      },
      if (refs.publicBooking != null) ...{
        'public_booking_reference': refs.publicBooking,
        'publicBookingReference': refs.publicBooking,
      },
      if (refs.booking != null) ...{
        'booking_reference': refs.booking,
        'bookingReference': refs.booking,
      },
      if (refs.publicRef != null) ...{
        'public_reference': refs.publicRef,
        'publicReference': refs.publicRef,
      },
      if (totalPackage != null) 'booking_total_eur': totalPackage,
      if (segmentPrice != null) 'segment_price_eur': segmentPrice,
      if (operationalLeg && segmentPrice != null) ...{
        'leg_price_incl_vat': segmentPrice,
        'legPriceInclVat': segmentPrice,
      },
      if (bookingMap['price_incl_vat_main'] != null ||
          pricingMain['price_incl_vat'] != null)
        'outbound_price_eur': number(
          bookingMap['price_incl_vat_main'] ?? pricingMain['price_incl_vat'],
        ),
      if (bookingMap['price_incl_vat_return'] != null ||
          pricingReturn['price_incl_vat'] != null)
        'return_price_eur': number(
          bookingMap['price_incl_vat_return'] ??
              pricingReturn['price_incl_vat'],
        ),
      if (returnPickup != null) 'return_scheduled_pickup_at': returnPickup,
      if (returnFrom != null || returnTo != null)
        'return_route': [returnFrom, returnTo].whereType<String>().join(' → '),
      if (routeSegments.isNotEmpty) 'route_segments': routeSegments,
      if (asList(
        bookingMap['stops'] ?? inputs['stops'] ?? quote['stops'],
      ).isNotEmpty)
        'stops': asList(
          bookingMap['stops'] ?? inputs['stops'] ?? quote['stops'],
        ).join(' → '),
      if (text(
            bookingMap['extra_service_label'] ?? inputs['extra_service_label'],
          ) !=
          null)
        'extras': text(
          bookingMap['extra_service_label'] ?? inputs['extra_service_label'],
        ),
      if (text(
            bookingMap['message'] ??
                payload['message'] ??
                customer['message'] ??
                pick([
                  ['customer', 'message'],
                ]),
          ) !=
          null)
        'notes': text(
          bookingMap['message'] ??
              payload['message'] ??
              customer['message'] ??
              pick([
                ['customer', 'message'],
              ]),
        ),
      if ((booking.currency ?? '').trim().isNotEmpty)
        'currency': booking.currency!.trim(),
    };
  }

  Future<void> _startDirectTripSessionOnWorker({
    required String destination,
  }) async {
    try {
      final strictScope = _strictBookingScopeForMutation(
        action: 'start_direct_trip',
      );
      if (strictScope == null) return;
      final point = _directRideDestinationPoint;
      final destinationPayload = <String, dynamic>{
        'label': destination,
        if (point != null) 'lat': point.lat,
        if (point != null) 'lon': point.lon,
      };
      final payload = <String, dynamic>{
        ...strictScope,
        'driver_id': kDriverId,
        'vehicle_id': _directRideVehicleId(),
        'origin': _currentOriginPayload(_lastPos),
        'destination': destinationPayload,
        'pricing_snapshot': _directRidePricingSnapshotPayload(),
        'client_started_at': (_trackingStartedAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        ..._driverMutationActorFields(actorVehicleId: _directRideVehicleId()),
      };
      final res = await http
          .post(
            _uriWithScope(kWorkerBaseUrl, kStartDirectTripPath, strictScope),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception('Invalid direct trip start response: ${res.body}');
      }
      final tripId = (decoded['trip_id'] ?? '').toString().trim();
      if (tripId.isEmpty) throw Exception('No trip_id returned');
      if (!mounted || !_directRideActive) return;
      setState(() {
        _activeDirectTripId = tripId;
        _directTripStartWorkerOk = true;
        _directTripStopWorkerOk = false;
      });
      debugPrint('[DIRECT_TRIP][START][OK] trip_id=$tripId');
    } catch (e) {
      debugPrint('[DIRECT_TRIP][START][WARN] local-only direct ride: $e');
    }
  }

  Future<double?> _stopDirectTripSessionOnWorker({
    required String tripId,
    required double kmTotal,
    required int waitSecondsTotal,
  }) async {
    try {
      final strictScope = _strictBookingScopeForMutation(
        action: 'stop_direct_trip',
        showUx: false,
      );
      if (strictScope == null) return null;
      final payload = <String, dynamic>{
        'trip_id': tripId,
        ...strictScope,
        'km_total': kmTotal,
        'wait_seconds_total': waitSecondsTotal,
        'client_stopped_at': DateTime.now().toUtc().toIso8601String(),
        ..._driverMutationActorFields(actorVehicleId: _directRideVehicleId()),
      };
      final res = await http
          .post(
            _uriWithScope(kWorkerBaseUrl, kStopDirectTripPath, strictScope),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception('Invalid direct trip stop response: ${res.body}');
      }
      final totals = decoded['totals'];
      final total = totals is Map ? totals['total_eur'] : null;
      _directTripStopWorkerOk = true;
      if (total is num) return total.toDouble();
      return double.tryParse((total ?? '').toString().replaceAll(',', '.'));
    } catch (e) {
      _directTripStopWorkerOk = false;
      debugPrint('[DIRECT_TRIP][STOP][WARN] using local total: $e');
      return null;
    }
  }

  Future<bool> _recordPlannedTripStopOnWorker({
    required BookingItem booking,
    required double kmTotal,
    required int waitSecondsTotal,
    required DateTime? startedAt,
    required DateTime stoppedAt,
  }) async {
    try {
      final strictScope = _strictBookingScopeForMutation(
        action: 'record_planned_trip_stop',
        showUx: false,
      );
      if (strictScope == null) return false;
      var bookingDetails = _plannedBookingDetailsPayload(booking);
      final authoritativeFields = await _fetchPaymentFieldsForHistory(
        booking.bookingId,
      );
      if (authoritativeFields.isNotEmpty) {
        bookingDetails = _mergeBusinessReferencesIntoSource(
          source: bookingDetails,
          authoritative: authoritativeFields,
          canonicalBookingId: booking.bookingId,
          tripId: null,
          sourceTag: 'planned_trip_stop_authoritative_fields',
        );
        bookingDetails.addAll(authoritativeFields);
        final existingBooking = bookingDetails['booking'];
        if (existingBooking is Map) {
          final mergedBooking = _mergeBusinessReferencesIntoSource(
            source: Map<String, dynamic>.from(existingBooking),
            authoritative: authoritativeFields,
            canonicalBookingId: booking.bookingId,
            tripId: null,
            sourceTag: 'planned_trip_stop_booking_nested',
          );
          if (authoritativeFields['payment_status'] != null) {
            mergedBooking['payment_status'] =
                authoritativeFields['payment_status'];
            mergedBooking['paymentStatus'] =
                authoritativeFields['payment_status'];
          }
          if (authoritativeFields['paid_at'] != null) {
            mergedBooking['paid_at'] = authoritativeFields['paid_at'];
            mergedBooking['paidAt'] = authoritativeFields['paid_at'];
          }
          if (authoritativeFields['payment_provider'] != null) {
            mergedBooking['payment_provider'] =
                authoritativeFields['payment_provider'];
            mergedBooking['paymentProvider'] =
                authoritativeFields['payment_provider'];
          }
          if (authoritativeFields['payment_id'] != null) {
            mergedBooking['payment_id'] = authoritativeFields['payment_id'];
            mergedBooking['paymentId'] = authoritativeFields['payment_id'];
          }
          bookingDetails['booking'] = mergedBooking;
        }
      }
      final legAmount = _driverDisplayPriceForBooking(booking);
      final price =
          legAmount ??
          (booking.isOperationalLeg
              ? null
              : (booking.price ??
                    BookingItem._toNumOrNull(
                      bookingDetails['booking_total_eur'],
                    )));
      final payload = <String, dynamic>{
        'booking_id': booking.bookingId,
        ...strictScope,
        'driver_id': kDriverId,
        'vehicle_id': _directRideVehicleId(),
        'origin': <String, dynamic>{
          'label': (booking.from ?? _receiptText('currentLocation')).toString(),
        },
        'destination': <String, dynamic>{
          'label': (booking.to ?? booking.from ?? booking.shortId).toString(),
          // The driver is physically at the drop-off when stopping a planned
          // ride. Booking records for this flow carry no drop-off coordinates,
          // so the live device GPS is the only trusted arrival coordinate
          // (Chiron aankomstpunt). Never send 0/0; omit when GPS is unavailable.
          if (_lastPos != null) 'lat': _lastPos!.latitude,
          if (_lastPos != null) 'lon': _lastPos!.longitude,
        },
        'booking_details': bookingDetails,
        if (startedAt != null)
          'started_at': startedAt.toUtc().toIso8601String(),
        'stopped_at': stoppedAt.toUtc().toIso8601String(),
        'km_total': kmTotal,
        'wait_seconds_total': waitSecondsTotal,
        if (price != null) 'total_eur': price.toDouble(),
        'currency': booking.currency ?? kDefaultCurrency,
        if (bookingDetails['payment_status'] != null)
          'payment_status': bookingDetails['payment_status'],
        if (bookingDetails['paymentStatus'] != null)
          'paymentStatus': bookingDetails['paymentStatus'],
        if (bookingDetails['paid_at'] != null)
          'paid_at': bookingDetails['paid_at'],
        if (bookingDetails['paidAt'] != null)
          'paidAt': bookingDetails['paidAt'],
        if (bookingDetails['payment_provider'] != null)
          'payment_provider': bookingDetails['payment_provider'],
        if (bookingDetails['paymentProvider'] != null)
          'paymentProvider': bookingDetails['paymentProvider'],
        if (bookingDetails['payment_id'] != null)
          'payment_id': bookingDetails['payment_id'],
        if (bookingDetails['paymentId'] != null)
          'paymentId': bookingDetails['paymentId'],
        if (bookingDetails['receipt_reference'] != null)
          'receipt_reference': bookingDetails['receipt_reference'],
        if (bookingDetails['planning_reference'] != null)
          'planning_reference': bookingDetails['planning_reference'],
        if (bookingDetails['public_booking_reference'] != null)
          'public_booking_reference':
              bookingDetails['public_booking_reference'],
        if (bookingDetails['booking_reference'] != null)
          'booking_reference': bookingDetails['booking_reference'],
        if (bookingDetails['public_reference'] != null)
          'public_reference': bookingDetails['public_reference'],
        ..._driverMutationActorFields(actorVehicleId: _directRideVehicleId()),
      };
      final res = await http
          .post(
            _uriWithScope(
              kWorkerBaseUrl,
              kRecordPlannedTripStopPath,
              strictScope,
            ),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      debugPrint('[PLANNED_TRIP][HISTORY][OK] booking=${booking.bookingId}');
      return true;
    } catch (e) {
      debugPrint(
        '[PLANNED_TRIP][HISTORY][WARN] booking=${booking.bookingId} reason=$e',
      );
      return false;
    }
  }

  String _complianceRideId({
    required String rideType,
    String? bookingId,
    String? tripId,
    required DateTime stoppedAt,
  }) {
    final seed = (bookingId ?? tripId ?? '').trim();
    final ts = stoppedAt.toUtc().millisecondsSinceEpoch;
    if (seed.isNotEmpty) return 'rlg_${rideType}_${seed}_$ts';
    return 'rlg_${rideType}_$ts';
  }

  String _complianceReceiptReference({
    String? bookingId,
    String? tripId,
    required String rideId,
  }) {
    final booking = (bookingId ?? '').trim();
    if (booking.isNotEmpty) return booking;
    final trip = (tripId ?? '').trim();
    if (trip.isNotEmpty) return 'TRIP-$trip';
    return rideId.trim();
  }

  String _complianceValidationState({
    required String rideType,
    required bool backendConfirmed,
    required String driverId,
    required String receiptReference,
    required DateTime? startedAt,
    required DateTime stoppedAt,
    String? bookingId,
  }) {
    if (driverId.trim().isEmpty ||
        driverId.trim() == kFallbackDriverTrackingId.trim()) {
      return 'blocked';
    }
    if (startedAt == null || startedAt.isAfter(stoppedAt)) return 'blocked';
    if (receiptReference.trim().isEmpty) return 'blocked';
    if (rideType == 'direct' && !backendConfirmed) return 'blocked';
    if (rideType == 'planned' && (bookingId ?? '').trim().isEmpty) {
      return 'incomplete';
    }
    return 'exportable';
  }

  String? _complianceText(dynamic value) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
  }

  String? _compliancePathText(Map<String, dynamic> root, String path) {
    dynamic cursor = root;
    for (final part in path.split('.')) {
      if (cursor is! Map) return null;
      cursor = cursor[part];
    }
    return _complianceText(cursor);
  }

  String? _firstComplianceText(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final text = _complianceText(candidate);
      if (text != null) return text;
    }
    return null;
  }

  String _normalizeCompliancePaymentStatus(dynamic value) {
    final raw = _complianceText(value);
    if (raw == null) return 'unknown';
    final normalized = raw
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .trim();
    switch (normalized) {
      case 'paid':
      case 'succeeded':
      case 'success':
      case 'completed':
      case 'settled':
      case 'confirmed':
        return 'paid';
      case 'pending':
      case 'open':
      case 'authorized':
      case 'authorised':
      case 'processing':
        return 'pending';
      case 'failed':
      case 'error':
      case 'declined':
        return 'failed';
      case 'cancelled':
      case 'canceled':
        return 'cancelled';
      case 'unpaid':
      case 'not_paid':
        return 'unpaid';
      case 'unknown':
        return 'unknown';
      default:
        return 'unknown';
    }
  }

  String _normalizeCompliancePaymentMethod(dynamic value) {
    final raw = _complianceText(value);
    if (raw == null) return 'unknown';
    final normalized = raw
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .trim();
    switch (normalized) {
      case 'cash':
      case 'contant':
        return 'cash';
      case 'qr':
      case 'qr_code':
        return 'qr';
      case 'bancontact':
        return 'bancontact';
      case 'card':
      case 'terminal':
      case 'card_terminal':
        return 'card_terminal';
      case 'payment_link':
      case 'link':
      case 'online':
        return 'payment_link';
      case 'mollie':
        return 'mollie';
      case 'in_car':
      case 'unknown':
        return 'unknown';
      default:
        return 'unknown';
    }
  }

  Map<String, dynamic> _buildCompliancePaymentPayload({
    dynamic status,
    dynamic method,
    dynamic source,
    dynamic provider,
    dynamic paymentId,
    dynamic paidAtUtc,
  }) {
    final normalizedStatus = _normalizeCompliancePaymentStatus(status);
    final normalizedMethod = _normalizeCompliancePaymentMethod(method);
    final sourceText = _complianceText(source);
    final providerText = _complianceText(provider);
    final paymentIdText = _complianceText(paymentId);
    final paidAtText = _complianceText(paidAtUtc);
    final parsedPaidAt = paidAtText == null
        ? null
        : DateTime.tryParse(paidAtText);

    return <String, dynamic>{
      'status': normalizedStatus,
      if (normalizedMethod != 'unknown') 'method': normalizedMethod,
      if (sourceText != null) 'source': sourceText,
      if (providerText != null) 'provider': providerText,
      if (paymentIdText != null) 'payment_id': paymentIdText,
      if (parsedPaidAt != null)
        'paid_at_utc': parsedPaidAt.toUtc().toIso8601String()
      else if (paidAtText != null)
        'paid_at_utc': paidAtText,
    };
  }

  Map<String, dynamic> _buildCompliancePlannedLedgerRecord({
    required BookingItem booking,
    required DateTime? startedAt,
    required DateTime stoppedAt,
    required double kmTotal,
    required int waitSecondsTotal,
    required bool backendConfirmed,
  }) {
    final bookingId = booking.bookingId.trim();
    final driverId = kDriverId.trim();
    final vehicleId = _directRideVehicleId().trim();
    final rideId = _complianceRideId(
      rideType: 'planned',
      bookingId: bookingId,
      stoppedAt: stoppedAt,
    );
    final receiptReference = _complianceReceiptReference(
      bookingId: bookingId,
      rideId: rideId,
    );
    final total =
        _driverDisplayPriceForBooking(booking) ??
        (booking.isOperationalLeg ? null : booking.price?.toDouble());
    final details = booking.details;
    final plannedPaymentStatus = _firstComplianceText([
      details['payment_status'],
      details['paymentStatus'],
      _compliancePathText(details, 'booking.payment_status'),
      _compliancePathText(details, 'booking.paymentStatus'),
      _compliancePathText(details, 'mollie.status'),
      _compliancePathText(details, 'record.mollie.status'),
    ]);
    final plannedPaymentMethod = _firstComplianceText([
      details['payment_method'],
      details['paymentMethod'],
      _compliancePathText(details, 'booking.payment_method'),
      _compliancePathText(details, 'booking.paymentMethod'),
    ]);
    final plannedPaymentSource = _firstComplianceText([
      details['payment_source'],
      details['paymentSource'],
      _compliancePathText(details, 'booking.payment_source'),
      _compliancePathText(details, 'booking.paymentSource'),
    ]);
    final plannedPaymentProvider = _firstComplianceText([
      details['payment_provider'],
      details['paymentProvider'],
      _compliancePathText(details, 'booking.payment_provider'),
      _compliancePathText(details, 'booking.paymentProvider'),
    ]);
    final plannedPaymentId = _firstComplianceText([
      details['payment_id'],
      details['paymentId'],
      _compliancePathText(details, 'booking.payment_id'),
      _compliancePathText(details, 'booking.paymentId'),
    ]);
    final plannedPaidAt = _firstComplianceText([
      details['paid_at'],
      details['paidAt'],
      _compliancePathText(details, 'booking.paid_at'),
      _compliancePathText(details, 'booking.paidAt'),
    ]);
    final referenceMaps = _referenceLookupMaps(<Map<String, dynamic>>[details]);
    final planningReference = _pickReferenceAliasFromMaps(referenceMaps, const [
      ['planning_reference'],
      ['planningReference'],
    ]);
    final publicBookingReference = _pickReferenceAliasFromMaps(
      referenceMaps,
      const [
        ['public_booking_reference'],
        ['publicBookingReference'],
        ['booking_reference'],
        ['bookingReference'],
        ['public_reference'],
        ['publicReference'],
      ],
    );
    final bookingReference = _pickReferenceAliasFromMaps(referenceMaps, const [
      ['booking_reference'],
      ['bookingReference'],
    ]);
    final publicReference = _pickReferenceAliasFromMaps(referenceMaps, const [
      ['public_reference'],
      ['publicReference'],
    ]);
    final effectiveReceiptReference = _pickBusinessReference(
      rawSource: details,
      details: details,
      bookingId: bookingId,
      tripId: null,
      legacyFallback: receiptReference,
    );
    final validationState = _complianceValidationState(
      rideType: 'planned',
      backendConfirmed: backendConfirmed,
      driverId: driverId,
      receiptReference: effectiveReceiptReference,
      startedAt: startedAt,
      stoppedAt: stoppedAt,
      bookingId: bookingId,
    );
    final ledgerScope = _complianceLedgerScopeForStop();

    return <String, dynamic>{
      'ledger_version': '1.0',
      'ride_id': rideId,
      'ride_type': 'planned',
      'lifecycle_status': 'completed',
      'tenant_id': ledgerScope?.tenantId ?? '',
      'company_id': ledgerScope?.companyId ?? '',
      'driver_id': driverId,
      'vehicle_id': vehicleId,
      'booking_id': bookingId,
      'trip_id': null,
      'session_id': _activeTripId,
      'started_at_utc': startedAt?.toUtc().toIso8601String(),
      'ended_at_utc': stoppedAt.toUtc().toIso8601String(),
      'duration_seconds': startedAt == null
          ? null
          : stoppedAt.difference(startedAt).inSeconds,
      'pickup': <String, dynamic>{'label': (booking.from ?? '').trim()},
      'dropoff': <String, dynamic>{'label': (booking.to ?? '').trim()},
      'distance_km': kmTotal,
      'wait_seconds_total': waitSecondsTotal,
      'fare': <String, dynamic>{
        'total_eur': total,
        'currency': booking.currency ?? kDefaultCurrency,
      },
      'payment': _buildCompliancePaymentPayload(
        status: plannedPaymentStatus,
        method: plannedPaymentMethod,
        source: plannedPaymentSource,
        provider: plannedPaymentProvider,
        paymentId: plannedPaymentId,
        paidAtUtc: plannedPaidAt,
      ),
      'references': <String, dynamic>{
        'receipt_reference': effectiveReceiptReference,
        'planning_reference': planningReference,
        'public_booking_reference': publicBookingReference,
        'booking_reference': bookingReference,
        'public_reference': publicReference,
        'invoice_reference': null,
      },
      'provenance': <String, dynamic>{
        'backend_confirmed': backendConfirmed,
        'validation_state': validationState,
      },
      'created_at_utc': DateTime.now().toUtc().toIso8601String(),
      'finalized_at_utc': stoppedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _buildComplianceDirectLedgerRecord({
    required String? tripId,
    required DateTime? startedAt,
    required DateTime stoppedAt,
    required double kmTotal,
    required int waitSecondsTotal,
    required double totalEur,
    required bool backendConfirmed,
  }) {
    final driverId = kDriverId.trim();
    final vehicleId = _directRideVehicleId().trim();
    final rideId = _complianceRideId(
      rideType: 'direct',
      tripId: tripId,
      stoppedAt: stoppedAt,
    );
    final receiptReference = _complianceReceiptReference(
      tripId: tripId,
      rideId: rideId,
    );
    final validationState = _complianceValidationState(
      rideType: 'direct',
      backendConfirmed: backendConfirmed,
      driverId: driverId,
      receiptReference: receiptReference,
      startedAt: startedAt,
      stoppedAt: stoppedAt,
    );
    final ledgerScope = _complianceLedgerScopeForStop();

    return <String, dynamic>{
      'ledger_version': '1.0',
      'ride_id': rideId,
      'ride_type': 'direct',
      'lifecycle_status': 'completed',
      'tenant_id': ledgerScope?.tenantId ?? '',
      'company_id': ledgerScope?.companyId ?? '',
      'driver_id': driverId,
      'vehicle_id': vehicleId,
      'booking_id': null,
      'trip_id': (tripId ?? '').trim().isEmpty ? null : tripId!.trim(),
      'session_id': null,
      'started_at_utc': startedAt?.toUtc().toIso8601String(),
      'ended_at_utc': stoppedAt.toUtc().toIso8601String(),
      'duration_seconds': startedAt == null
          ? null
          : stoppedAt.difference(startedAt).inSeconds,
      'pickup': _currentOriginPayload(_startPos ?? _lastPos),
      'dropoff': <String, dynamic>{
        'label': (_directRideDestinationText ?? '').trim(),
        if (_directRideDestinationPoint != null)
          'lat': _directRideDestinationPoint!.lat,
        if (_directRideDestinationPoint != null)
          'lon': _directRideDestinationPoint!.lon,
      },
      'distance_km': kmTotal,
      'wait_seconds_total': waitSecondsTotal,
      'fare': <String, dynamic>{
        'total_eur': totalEur,
        'currency': kDefaultCurrency,
      },
      'payment': _buildCompliancePaymentPayload(),
      'references': <String, dynamic>{
        'receipt_reference': receiptReference,
        'planning_reference': null,
        'public_booking_reference': null,
        'booking_reference': null,
        'public_reference': null,
        'invoice_reference': null,
      },
      'provenance': <String, dynamic>{
        'backend_confirmed': backendConfirmed,
        'validation_state': validationState,
      },
      'created_at_utc': DateTime.now().toUtc().toIso8601String(),
      'finalized_at_utc': stoppedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _buildLocalOnlyDirectHistoryRecord({
    required DateTime stoppedAt,
    required DateTime? startedAt,
    required double kmTotal,
    required int waitSecondsTotal,
    required double totalEur,
  }) {
    final localTripId =
        'local_direct_${stoppedAt.toUtc().millisecondsSinceEpoch}';
    final origin = _currentOriginPayload(_startPos ?? _lastPos);
    final destination = <String, dynamic>{
      'label': (_directRideDestinationText ?? '').trim(),
      if (_directRideDestinationPoint != null)
        'lat': _directRideDestinationPoint!.lat,
      if (_directRideDestinationPoint != null)
        'lon': _directRideDestinationPoint!.lon,
    };
    final payment = _buildCompliancePaymentPayload();

    return <String, dynamic>{
      'trip_id': localTripId,
      'kind': 'direct',
      'status': 'COMPLETED',
      'tenant_id': kOutboundTenantId,
      'driver_id': kDriverId,
      'vehicle_id': _directRideVehicleId(),
      'started_at': startedAt?.toUtc().toIso8601String(),
      'stopped_at': stoppedAt.toUtc().toIso8601String(),
      'origin': origin,
      'destination': destination,
      'km_total': kmTotal,
      'wait_seconds_total': waitSecondsTotal,
      'total_eur': totalEur,
      'currency': kDefaultCurrency,
      'payment_status': payment['status'] ?? 'unknown',
      'booking_details': <String, dynamic>{
        'payment_status': payment['status'] ?? 'unknown',
        if (payment['method'] != null) 'payment_method': payment['method'],
        if (payment['source'] != null) 'payment_source': payment['source'],
        if (payment['provider'] != null)
          'payment_provider': payment['provider'],
        if (payment['payment_id'] != null) 'payment_id': payment['payment_id'],
        if (payment['paid_at_utc'] != null) 'paid_at': payment['paid_at_utc'],
        'history_source': 'local_only_direct_fallback',
        'backend_confirmed': false,
      },
      'history_source': 'local_only_direct_fallback',
      'backend_confirmed': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<void> _persistLocalOnlyDirectHistoryFallback({
    required DateTime stoppedAt,
    required DateTime? startedAt,
    required double kmTotal,
    required int waitSecondsTotal,
    required double totalEur,
  }) async {
    final record = _buildLocalOnlyDirectHistoryRecord(
      stoppedAt: stoppedAt,
      startedAt: startedAt,
      kmTotal: kmTotal,
      waitSecondsTotal: waitSecondsTotal,
      totalEur: totalEur,
    );
    await _LocalDirectTripHistoryStore.append(record);
  }

  Future<void> _stopTrip() async {
    final trip = _activeTripId;
    if (trip == null && !_directRideActive) return;
    final stoppedBooking = _activeBooking;
    if (stoppedBooking != null &&
        !_canOperateBookingWithGuard(
          _bookingScopeViewFor(stoppedBooking),
          action: 'stop_complete_booking',
        )) {
      return;
    }
    final wasDirectRide = _directRideActive;
    final directTripId = _activeDirectTripId;
    final finalTotal = _liveMeterTotalEur;
    final stoppedAt = DateTime.now();
    final startedAt = _trackingStartedAt;
    final kmAtStop = _kmDriven;
    var plannedSessionStopOk = false;

    if (_isWaiting && _waitStartedAt != null) {
      final started = _waitStartedAt!;
      _waitElapsed += DateTime.now().difference(started);
      _waitStartedAt = null;
      _isWaiting = false;
    }

    if (trip != null) {
      try {
        final strictScope = _strictBookingScopeForMutation(
          action: 'stop_trip_session',
          showUx: false,
        );
        if (strictScope == null) return;
        final uri = _uriWithScope(kWorkerBaseUrl, kStopTripPath, strictScope);
        final payload = <String, dynamic>{
          'session_id': trip,
          'driver_id': kDriverId,
          ...strictScope,
          ..._driverMutationActorFields(actorVehicleId: _directRideVehicleId()),
        };
        final res = await http
            .post(
              uri,
              headers: _headers(admin: true),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));
        plannedSessionStopOk = res.statusCode == 200;
      } catch (_) {}
    }

    var plannedTripStopBridgeOk = false;
    if (!wasDirectRide && stoppedBooking != null && plannedSessionStopOk) {
      plannedTripStopBridgeOk = await _recordPlannedTripStopOnWorker(
        booking: stoppedBooking,
        kmTotal: kmAtStop,
        waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
      );
    }

    double? serverDirectTotal;
    if (wasDirectRide &&
        directTripId != null &&
        directTripId.trim().isNotEmpty) {
      serverDirectTotal = await _stopDirectTripSessionOnWorker(
        tripId: directTripId,
        kmTotal: _kmDriven,
        waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
      );
    }

    _stopMeterTicker();
    _stopTrackingInternal();

    if (stoppedBooking != null) {
      await _completeStoppedBooking(
        stoppedBooking,
        plannedStopBridgeAlreadyCompletedLeg: plannedTripStopBridgeOk,
      );
    }
    if (!wasDirectRide && stoppedBooking != null) {
      final plannedLedger = _buildCompliancePlannedLedgerRecord(
        booking: stoppedBooking,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
        kmTotal: kmAtStop,
        waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
        backendConfirmed: plannedSessionStopOk,
      );
      unawaited(_writeComplianceLedgerRecord(record: plannedLedger));
    }
    if (wasDirectRide) {
      final directBackendConfirmed =
          _directTripStartWorkerOk && _directTripStopWorkerOk;
      final finalDirectTotal = serverDirectTotal ?? finalTotal;
      final directLedger = _buildComplianceDirectLedgerRecord(
        tripId: directTripId,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
        kmTotal: _kmDriven,
        waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
        totalEur: finalDirectTotal,
        backendConfirmed: directBackendConfirmed,
      );
      unawaited(_writeComplianceLedgerRecord(record: directLedger));
      final isLocalOnlyDirect =
          directTripId == null || directTripId.trim().isEmpty;
      if (isLocalOnlyDirect) {
        await _persistLocalOnlyDirectHistoryFallback(
          stoppedAt: stoppedAt,
          startedAt: startedAt,
          kmTotal: _kmDriven,
          waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
          totalEur: finalDirectTotal,
        );
      }
      _directTripStartWorkerOk = false;
      _directTripStopWorkerOk = false;
    }
    await _clearActiveRouteAndNavigationState(
      reason: 'stop',
      bookingId: stoppedBooking?.bookingId,
      clearActiveSelection: true,
    );
    if (wasDirectRide) {
      final shownTotal = serverDirectTotal ?? finalTotal;
      _toast('Straatrit afgerond: € ${shownTotal.toStringAsFixed(2)}');
    }
    unawaited(_refreshCompletedTodayCount(reason: 'trip_stop'));
  }

  Future<void> _completeStoppedBooking(
    BookingItem b, {
    bool plannedStopBridgeAlreadyCompletedLeg = false,
  }) async {
    final bookingId = b.bookingId;
    final rowKey = b.rowKey;
    final legId = b.legId.trim();
    final isLegScopedCompletion = b.isOperationalLeg && legId.isNotEmpty;
    final legType = isLegScopedCompletion ? _operationalLegTypeToken(b) : '-';
    final previousStatus = (b.status ?? '').trim();
    debugPrint(
      '[ROUNDTRIP_STATUS][LEG_COMPLETE] parent=$bookingId leg=${legId.isEmpty ? "-" : legId} leg_type=$legType old=${previousStatus.isEmpty ? "-" : previousStatus} new=COMPLETED scope=${isLegScopedCompletion ? "leg" : "parent"} source=driver_cockpit_stop',
    );
    // Roundtrip operational-leg false toast suppression: when the planned trip
    // stop bridge already accepted this leg's completion (worker-side bridge
    // applies COMPLETED with bypass_future_pickup_guard), a second direct call
    // through /bookings/:id/legs/:leg/status would be rejected by the future-
    // pickup guard for legs whose booked pickup is still in the future. That
    // produced the spurious "Legstatus bijwerken mislukt" toast even though
    // backend state is already correct. Trust the bridge for leg scope.
    final shouldSkipLegStatusCall =
        isLegScopedCompletion && plannedStopBridgeAlreadyCompletedLeg;
    if (shouldSkipLegStatusCall) {
      debugPrint(
        '[ROUNDTRIP_STATUS][FALSE_TOAST_SUPPRESSED] parent=$bookingId leg=${legId.isEmpty ? "-" : legId} leg_type=$legType reason=planned_stop_bridge_already_completed_leg source=driver_cockpit_stop',
      );
    } else {
      try {
        if (isLegScopedCompletion) {
          // Roundtrip operational-leg completion scope: complete only this leg.
          // Routing through the parent endpoint cascades COMPLETED onto every
          // sibling leg and hides the still-open return leg from the driver.
          await _setOperationalLegStatus(b, 'COMPLETED');
        } else {
          await _setBookingStatus(b, 'COMPLETED');
        }
      } catch (e) {
        debugPrint('[RIDES][STOP_COMPLETE][WARN] $e');
      }
    }
    if (!mounted) return;
    setState(() {
      if (isLegScopedCompletion) {
        // Optimistic state is leg-scoped: never stamp the parent booking_id
        // override or _deletedBookingIds, both of which are matched against
        // sibling leg rows that share the same bookingId and would hide the
        // return leg from the driver list before the worker refresh lands.
        _bookingStatusOverrides[rowKey] = 'COMPLETED';
        _bookings.removeWhere((x) => x.rowKey == rowKey);
        final remainingLegRows = _bookings
            .where(
              (x) =>
                  x.bookingId == bookingId &&
                  x.rowKey != rowKey &&
                  !_isClosedRideStatus(_effectiveStatusFor(x)),
            )
            .length;
        debugPrint(
          '[ROUNDTRIP_STATUS][KEEP_RETURN_VISIBLE] parent=$bookingId completed_row_key=$rowKey completed_leg=$legId leg_type=$legType remaining_open_leg_rows=$remainingLegRows',
        );
      } else {
        _bookingStatusOverrides[bookingId] = 'COMPLETED';
        _bookings.removeWhere((x) => x.bookingId == bookingId);
        _deletedBookingIds.add(bookingId);
      }
    });
    _markBookingsUiDirty();
    if (shouldSkipLegStatusCall) {
      // We skipped _setOperationalLegStatus which normally drives the post-
      // mutation snapshot fetch and refresh. Trigger the same reconciliation
      // here so the driver list, customer overlay and worker projection stay
      // aligned with the bridge-applied leg completion.
      unawaited(
        _debugFetchBookingSnapshot(
          bookingId: bookingId,
          contextLabel: 'LEG_STATUS_AFTER_PLANNED_STOP_BRIDGE',
        ),
      );
      unawaited(
        _refreshBookings(
          force: true,
          trigger: 'planned_stop_bridge_handled_leg',
        ),
      );
    }
  }

  Future<void> _ensureLocationPermission() async {
    final enabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _toast('Location is disabled on the phone.');
      return;
    }

    geo.LocationPermission perm = await geo.Geolocator.checkPermission();
    if (perm == geo.LocationPermission.denied) {
      perm = await geo.Geolocator.requestPermission();
    }
    if (perm == geo.LocationPermission.denied ||
        perm == geo.LocationPermission.deniedForever) {
      _toast('Location permission denied.');
      return;
    }
  }

  void _startTrackingInternal() {
    if (_posSub != null) {
      debugPrint(
        '[RIDES][TRACKING][SKIP_START] reason=already_active geolocatorSubs=$_activeGeolocatorSubscriptionCount',
      );
      return;
    }
    _stopBookingPolling(reason: 'tracking_started');

    final settings = buildDriverTrackingLocationSettings();

    _posSub = geo.Geolocator.getPositionStream(locationSettings: settings).listen((
      pos,
    ) async {
      final prev = _lastPos;
      _lastPos = pos;
      _startPos ??= pos;

      if (prev != null) {
        final meters = geo.Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (meters.isFinite && meters > 0) {
          // Only count driven distance once the trip is actually started.
          if (_liveRideActive && !_isWaiting) {
            if (mounted) setState(() => _kmDriven += meters / 1000.0);
          } else if (_liveRideActive && _isWaiting) {
            debugPrint(
              '[METER][WAIT_DISTANCE_SKIPPED] meters=${meters.toStringAsFixed(1)} km=${_kmDriven.toStringAsFixed(3)}',
            );
          }
        }

        if (_liveRideActive && !_hasSwitchedToFollow && _startPos != null) {
          final movedFromStart = geo.Geolocator.distanceBetween(
            _startPos!.latitude,
            _startPos!.longitude,
            pos.latitude,
            pos.longitude,
          );
          final speedKmh = (pos.speed.isFinite ? (pos.speed * 3.6) : 0.0);
          if (speedKmh >= 3.0 || movedFromStart >= 25.0) {
            _hasSwitchedToFollow = true;
            _cameraMode = _CameraMode.follow;
          }
        }

        final movementBearing = _bearingFromPoints(
          prev.latitude,
          prev.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (movementBearing != null && meters >= 1.8) {
          _lastMovementBearing = movementBearing;
        }
      }

      if (pos.heading.isFinite &&
          pos.heading >= 0 &&
          _speedKmhFor(pos) >= 2.0) {
        _lastKnownBearing = pos.heading;
      }

      _updateRouteSnapState(pos);
      _evaluateOffRouteReroute();

      // NAV-R12-D: marker geometry/rotation updates first and without
      // awaiting route redraw / camera / diagnostics — the taxi must move
      // on the fresh fix, not after the heavy pipeline. Manager loss no
      // longer blocks this path; it triggers self-heal instead.
      final canDriveMap = _mapSupported && _map != null && !_mapStyleChanging;
      if (canDriveMap) {
        _refreshNavEngineForPosition(pos);
        _scheduleDriverMarkerFastUpdate(pos);
        // NAV-R12-E1: camera follow schedules on the fresh fix too, not
        // behind the awaited route-line/diagnostics work. Throttle,
        // in-flight, and GPS-quality gates live inside _followCameraTesla;
        // queued targets use last-wins semantics.
        if (_cameraMode == _CameraMode.follow) {
          unawaited(_followCameraTesla(pos));
        }
      }

      await _syncVisibleRouteLineWithProgress(pos);
      _syncNavDiagSession();
      _recordNavDiagGpsUpdate(
        pos,
        prev,
        metersFromPrev: prev != null
            ? geo.Geolocator.distanceBetween(
                prev.latitude,
                prev.longitude,
                pos.latitude,
                pos.longitude,
              )
            : null,
      );
      _maybeAddNavValidationSample(pos);
      final uiBearing = _adaptiveBearingFor(pos, snap: _lastRouteSnap).bearing;
      if (mounted && _cameraMode == _CameraMode.follow) {
        setState(() => _uiArrowBearing = uiBearing);
      } else {
        _uiArrowBearing = uiBearing;
      }
      _updateNextNavInstruction(pos);

      await _sendPing(pos);
    });
    _activeGeolocatorSubscriptionCount = 1;
    debugPrint(
      '[RIDES][TRACKING][START] geolocatorSubs=$_activeGeolocatorSubscriptionCount',
    );
  }

  void _stopTrackingInternal() {
    if (_posSub == null) return;
    _resetNavValidationState(flushReport: true);
    _posSub?.cancel();
    _posSub = null;
    _activeGeolocatorSubscriptionCount = 0;
    debugPrint(
      '[RIDES][TRACKING][STOP] geolocatorSubs=$_activeGeolocatorSubscriptionCount',
    );
    _startPos = null;
    _lastFollowCameraAt = null;
    _followCameraInFlight = false;
    _gpsQualityWeak = false;
    _lastSmoothedCameraBearing = null;
    // NAV-R12-D: active navigation stopped — reset marker self-heal state.
    _markerSelfHealTimer?.cancel();
    _markerSelfHealTimer = null;
    _pendingMarkerUpdatePos = null;
    _consecutiveMarkerUpdateFailures = 0;
    _markerLifecycle.reset();
    // NAV-R12-E1: drop any queued camera target.
    _resetPendingFollowCamera();
    _driverNavEngine.reset();
    _lastNavEngineOutput = null;
    _lastNavEngineRefreshKey = null;
    _resetNavR3MotionState();
    _resetNavRouteProgressState();
    _resetNavCameraPolicyState();
    _resetNavConfidenceState();
    _resetNavComplexityState();
    _resetNavMotionPredictionState();
    _resetNavInstructionPolicyState();
    if (!_liveRideActive) {
      _startBookingPolling(reason: 'tracking_stopped');
    }
  }

  /// ===============================
  /// HUD COMPUTED TEXTS (single source of truth)
  /// ===============================

  bool get _isTracking => _liveRideActive && _posSub != null;

  String get _etaText {
    // Countdown style ETA (remaining), used both in preview and in active trip.
    final total = _routeDurationSec;
    if (total == null || total <= 0) return '';

    // When tracking, subtract progress (based on km fraction). When previewing, show total.
    int remainingSec;
    if (_isTracking) {
      remainingSec = _timeRemainingSeconds ?? total;
    } else {
      // Not tracking yet (preview)
      remainingSec = total;
    }

    remainingSec = math.max(0, remainingSec);
    if (remainingSec < 60) return '<1 min';

    final minutes = (remainingSec / 60).ceil();
    if (minutes < 60) return '$minutes min';

    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String get _kmRemainingText {
    // Show in preview as soon as we have a route.

    final remaining = _kmRemaining;
    if (remaining == null) return '';
    if (remaining < 0.05) return '0.0';
    return remaining.toStringAsFixed(1);
  }

  String get _timeRemainingText {
    if (!_isTracking) return '';
    final sec = _timeRemainingSeconds;
    if (sec == null) return '';
    final minutes = (sec / 60.0).round();
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m';
  }

  double? get _kmRemaining {
    final rk = _routeKm;
    if (rk == null) return null;

    // ✅ Countdown starts only once we actually move (Google Maps style).
    // Before movement, keep the full route distance as "remaining".
    if (_isTracking && !_hasSwitchedToFollow) return rk;

    final v = rk - _kmDriven;
    return v < 0 ? 0 : v;
  }

  int? get _timeRemainingSeconds {
    final total = _routeDurationSec;
    final rk = _routeKm;
    if (total == null || rk == null) return null;

    // ✅ Countdown starts only once we actually move (Google Maps style).
    if (_isTracking && !_hasSwitchedToFollow) return total;

    if (rk <= 0.01) return total;
    final fracDriven = (_kmDriven / rk).clamp(0.0, 1.0);
    final remaining = (total * (1.0 - fracDriven)).round();
    return remaining < 0 ? 0 : remaining;
  }

  /// Map HUD actions
  Future<void> _stopTracking() async {
    // Stop UI + pings immediately (best UX)
    _stopTrackingInternal();

    // Try to notify Worker (best-effort)
    try {
      await _stopTrip();
    } catch (_) {
      // ignore
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openNavigation() async {
    // NAV always forces follow mode for live street-level navigation.
    if (_map == null) return;
    final booking = _activeBooking;
    if (booking != null &&
        !_canOperateBookingWithGuard(
          _bookingScopeViewFor(booking),
          action: 'open_navigation',
        )) {
      _logDriverNavDiag(
        tag: 'BLOCK',
        action: 'open_navigation',
        bookingId: booking.bookingId,
      );
      return;
    }
    _logDriverNavDiag(
      tag: 'OPEN_RIDE',
      action: 'open_navigation',
      bookingId: booking?.bookingId,
    );
    if (_isBusinessPreviewMode) {
      _logDriverNavDiag(
        tag: 'BUSINESS_PREVIEW_KEEP_DRIVER',
        action: 'open_navigation',
        bookingId: booking?.bookingId,
      );
    }

    setState(() {
      _cameraMode = _CameraMode.follow;
      _hasSwitchedToFollow = true;
      _followCar = true;
      _allowOverviewCamera = false;
    });
    _setNavigationWakelock(true);
    await _applyMapStyleForMode();
    await _syncMapboxUserLocationPuckVisibility();
    await _forceFollowCameraNow(caller: 'nav_button');
    final b = _activeBooking;
    if (b != null && _activeTripId == null) {
      await _buildNavRouteToPickup(b);
    } else if (b != null && _activeTripId != null) {
      await _buildNavRouteToDestination(b);
    } else if ((_directRideDestinationText ?? '').trim().isNotEmpty) {
      await _buildDirectRouteToDestination(_directRideDestinationText!.trim());
    }
  }

  Future<void> _openDirectRideEntry() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    final destination = await showDialog<DirectRideDestinationResult>(
      context: context,
      builder: (_) => DirectRideDestinationDialog(
        themeListenable: _activeDriverThemeListenable,
        initialText: _directRideDestinationText ?? '',
        search: (query) async {
          final results = await _fetchPlaceSuggestions(query);
          return results
              .map(
                (s) => DirectRideSuggestion(
                  label: s.label,
                  lon: s.lon,
                  lat: s.lat,
                ),
              )
              .toList(growable: false);
        },
        tr: _tr,
      ),
    );
    if (!mounted || destination == null || destination.label.trim().isEmpty)
      return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final selectedPoint = (destination.lon != null && destination.lat != null)
        ? _LonLat(destination.lon!, destination.lat!)
        : null;

    setState(() {
      _activeBooking = null;
      _activeTripId = null;
      _activeDirectTripId = null;
      _directRideActive = false;
      _directTripStartWorkerOk = false;
      _directTripStopWorkerOk = false;
      _directRideDestinationText = destination.label.trim();
      _directRideDestinationPoint = selectedPoint;
      _kmDriven = 0.0;
      _resetNavProgressState(clearRoute: true);
      _routePhase = _RideRoutePhase.trip;
      _cameraMode = _CameraMode.overview;
      _hasSwitchedToFollow = false;
      _followCar = false;
      _allowOverviewCamera = false;
      _isWaiting = false;
      _waitStartedAt = null;
      _waitElapsed = Duration.zero;
      _trackingStartedAt = null;
      _directRideEstimatedFare = null;
      _directRideEstimateLoading = false;
      _directRideEstimateError = null;
      _directRideEstimateCurrency = kDefaultCurrency;
      _directRideEstimateSignature = null;
      _directRideLocationRetryCount = 0;
      _directRideLocationRetryDestination = _directRideDestinationText;
    });
    _toast('Straatrit klaar. Druk START om te rijden.');
    _scheduleDirectRideEstimateRefresh(reason: 'destination_changed');
  }

  Future<void> _startDirectRide() async {
    final destination = (_directRideDestinationText ?? '').trim();
    if (destination.isEmpty) {
      await _openDirectRideEntry();
      return;
    }
    await _ensureLocationPermission();
    var pos = _lastPos;
    if (pos == null) {
      try {
        pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.best,
        );
        _lastPos = pos;
      } catch (_) {
        pos = null;
      }
    }
    if (pos == null) {
      _toast('GPS-locatie nog niet beschikbaar');
      return;
    }

    setState(() {
      _directRideActive = true;
      _activeTripId = null;
      _activeDirectTripId = null;
      _directTripStartWorkerOk = false;
      _directTripStopWorkerOk = false;
      _activeBooking = null;
      _cameraMode = _CameraMode.follow;
      _hasSwitchedToFollow = true;
      _followCar = true;
      _allowOverviewCamera = false;
      _kmDriven = 0.0;
      _trackingStartedAt = DateTime.now();
      _isWaiting = false;
      _waitStartedAt = null;
      _waitElapsed = Duration.zero;
    });
    _setNavigationWakelock(true);
    await _applyMapStyleForMode();
    _startTrackingInternal();
    _startMeterTicker();
    unawaited(_startDirectTripSessionOnWorker(destination: destination));
    await _forceFollowCameraNow(caller: 'direct_ride_start');
    await _buildDirectRouteToDestination(destination);
  }

  void _handleCockpitStart() {
    final b = _activeBooking;
    if (b != null) {
      _startTrip(b);
      return;
    }
    if (_directRideDraft || _directRideActive) {
      _startDirectRide();
      return;
    }
    _toast('Kies eerst een rit of start een straatrit.');
  }

  Future<void> _sendPing(geo.Position pos) async {
    final trip = _activeTripId;
    if (trip == null) return;

    try {
      final strictScope = _strictBookingScopeForMutation(
        action: 'trip_ping',
        showUx: false,
      );
      if (strictScope == null) return;
      final uri = _uriWithScope(kWorkerBaseUrl, kPingPath, strictScope);
      final actorVehicleId = _directRideVehicleId();
      final payload = {
        'session_id': trip,
        'driver_id': kDriverId,
        'vehicle_id': actorVehicleId,
        ...strictScope,
        'lat': pos.latitude,
        'lon': pos.longitude,
        'speed': (pos.speed.isFinite ? (pos.speed * 3.6) : 0.0),
        'heading': (pos.heading.isFinite ? pos.heading : 0.0),
        'accuracy_m': pos.accuracy,
        'ts': DateTime.now().toIso8601String(),
        ..._driverMutationActorFields(actorVehicleId: actorVehicleId),
      };

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      setState(() {
        _pingCount += 1;
        _lastPing = (res.statusCode == 200) ? 'OK' : 'HTTP ${res.statusCode}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastPing = 'ERR');
    }
  }

  Future<void> _onMapCreated(mb.MapboxMap mapboxMap) async {
    debugPrint('[MAP][CREATED] style=$_activeMapStyleUri');
    _map = mapboxMap;
    await _syncMapboxUserLocationPuckVisibility();
    await _applyMapStyleForMode();
    await _recreateAnnotationManagers();
    await _syncMapboxUserLocationPuckVisibility();

    final pos = _lastPos;
    if (pos != null) {
      await _updateDriverMarker(
        pos,
        moveCamera: _cameraMode != _CameraMode.follow,
      );
      if (_cameraMode == _CameraMode.follow) {
        await _followCameraTesla(pos, force: true);
      }
    }
  }

  bool _hasActiveDriverTaxiMarker() {
    return _driverMarker != null &&
        _driverPointManager != null &&
        !_mapStyleChanging;
  }

  bool _isFluxidiRoutePreviewOrNav() {
    return _liveRideActive ||
        _directRideActive ||
        _directRideDraft ||
        _activeBooking != null ||
        _routeCoords.length >= 2 ||
        _cameraMode == _CameraMode.follow;
  }

  String _puckHideReason() {
    if (_isFluxidiRoutePreviewOrNav()) return 'route_context';
    if (_hasActiveDriverTaxiMarker()) return 'has_taxi_marker';
    if (_cameraMode == _CameraMode.follow && _liveRideActive) {
      return 'follow_live';
    }
    return 'idle';
  }

  bool _shouldHideMapboxUserLocationPuck() {
    if (_isFluxidiRoutePreviewOrNav()) return true;
    if (_hasActiveDriverTaxiMarker()) return true;
    return _cameraMode == _CameraMode.follow && _liveRideActive;
  }

  Future<void> _syncMapboxUserLocationPuckVisibility() async {
    final map = _map;
    if (map == null || !_mapSupported) return;

    final hide = _shouldHideMapboxUserLocationPuck();
    final reason = _puckHideReason();
    try {
      if (hide) {
        if (!_mapboxLocationPuckSuppressedForNav) {
          final settings = await map.location.getSettings();
          _mapboxLocationPuckRestoreEnabled = settings.enabled ?? false;
          _mapboxLocationPuckSuppressedForNav = true;
        }
        await map.location.updateSettings(
          mb.LocationComponentSettings(
            enabled: false,
            pulsingEnabled: false,
            showAccuracyRing: false,
            puckBearingEnabled: false,
          ),
        );
      } else if (_mapboxLocationPuckSuppressedForNav) {
        await map.location.updateSettings(
          mb.LocationComponentSettings(
            enabled: _mapboxLocationPuckRestoreEnabled,
          ),
        );
        _mapboxLocationPuckSuppressedForNav = false;
      }

      if (_lastSyncedMapboxPuckHidden != hide) {
        _lastSyncedMapboxPuckHidden = hide;
        _logNavBounded(
          'NAV_UI_R6D_PUCK',
          'hidden=$hide reason=$reason follow=${_cameraMode == _CameraMode.follow} live=$_liveRideActive',
          intervalMs: 3000,
        );
      }
    } catch (_) {
      _logNavBounded(
        'NAV_UI_R6D_PUCK',
        'hidden=$hide reason=sync_failed',
        intervalMs: 5000,
      );
    }
  }

  bool get _canUpdateDriverMarker =>
      !_mapStyleChanging && _map != null && _driverPointManager != null;

  bool _isMapboxAnnotationManagerLost(Object e) {
    final blob = e.toString().toLowerCase();
    if (e is PlatformException) {
      final message = (e.message ?? '').toLowerCase();
      final details = (e.details?.toString() ?? '').toLowerCase();
      return blob.contains('no manager found') ||
          message.contains('no manager found') ||
          details.contains('no manager found');
    }
    return blob.contains('no manager found');
  }

  void _resetDriverMarkerOnNativeError(String reason) {
    debugPrint('[NAV_MARKER] manager_reset reason=$reason');
    unawaited(
      NavDiagnosticsRecorder.instance.recordException(
        context: 'marker_manager_reset',
        error: StateError(reason),
      ),
    );
    _driverPointManager = null;
    _driverMarker = null;
    _driverMarkerUsesTaxiAsset = false;
    // NAV-R12-D: a lost manager must not stay lost until the next style
    // swap — mark degraded and schedule a bounded self-heal.
    _markerLifecycle.noteFailure(reason, DateTime.now());
    _scheduleMarkerSelfHeal(reason);
  }

  /// NAV-R12-D: bounded, PII-safe marker lifecycle diagnostics (no lat/lng).
  void _logNavR12Marker({
    required String event,
    String? markerSource,
    int? markerLagMs,
    String? selfHealReason,
    int? recreateAttempt,
  }) {
    final managerReady = _driverPointManager != null && !_mapStyleChanging;
    final signature =
        '$event|$managerReady|${_markerLifecycle.degraded}|'
        '${selfHealReason ?? ''}';
    final changed = signature != _lastNavR12MarkerSignature;
    _lastNavR12MarkerSignature = signature;
    _logNavBounded(
      'NAV_R12_MARKER',
      'markerUpdate=$event '
          'markerSource=${markerSource ?? 'na'} '
          'markerLagMs=${markerLagMs ?? -1} '
          'managerReady=$managerReady '
          'managerDegraded=${_markerLifecycle.degraded} '
          'updateInFlight=${_markerLifecycle.updateInFlight} '
          'pendingUpdate=${_markerLifecycle.pendingUpdate} '
          'selfHealScheduled=${_markerSelfHealTimer?.isActive ?? false} '
          'selfHealReason=${selfHealReason ?? _markerLifecycle.lastFailureReason} '
          'recreateAttempt=${recreateAttempt ?? _markerLifecycle.selfHealAttempts}',
      intervalMs: changed ? 1 : 2000,
    );
    if (changed && event.startsWith('self_heal')) {
      unawaited(
        NavDiagnosticsRecorder.instance.recordNavEngineEvent(
          tag: 'NAV_R12_MARKER',
          fields: <String, dynamic>{
            'event': event,
            'managerReady': managerReady,
            'managerDegraded': _markerLifecycle.degraded,
            'selfHealReason':
                selfHealReason ?? _markerLifecycle.lastFailureReason,
            'recreateAttempt':
                recreateAttempt ?? _markerLifecycle.selfHealAttempts,
          },
        ),
      );
    }
  }

  /// NAV-R12-D: schedule one self-heal attempt on the lifecycle backoff.
  /// Idempotent — an already-armed timer wins.
  void _scheduleMarkerSelfHeal(String reason) {
    if (!_mapSupported || !mounted) return;
    if (_markerSelfHealTimer?.isActive ?? false) return;
    final delay = _markerLifecycle.selfHealDelay(DateTime.now());
    _logNavR12Marker(event: 'self_heal_scheduled', selfHealReason: reason);
    _markerSelfHealTimer = Timer(delay, () {
      _markerSelfHealTimer = null;
      unawaited(_attemptMarkerSelfHeal(reason));
    });
  }

  /// NAV-R12-D: recreate the annotation manager and taxi marker after a
  /// native failure. Never throws; failure re-arms the backoff timer.
  Future<void> _attemptMarkerSelfHeal(String reason) async {
    if (!mounted) return;
    if (_map == null || _mapStyleChanging) {
      // Style swap has its own recreate/restore path; check back later.
      if (_markerLifecycle.degraded) _scheduleMarkerSelfHeal(reason);
      return;
    }
    if (!_markerLifecycle.degraded && _driverMarker != null) {
      return; // healed in the meantime (e.g. by a style-swap restore)
    }
    final attempt = _markerLifecycle.noteSelfHealAttemptStarted(DateTime.now());
    _logNavR12Marker(
      event: 'self_heal_attempt',
      selfHealReason: reason,
      recreateAttempt: attempt,
    );
    var success = false;
    try {
      if (_driverPointManager == null) {
        final mgr = await _map!.annotations.createPointAnnotationManager();
        await _configureDriverPointManagerForTaxiMarker(mgr);
        _driverPointManager = mgr;
      }
      success = await _attemptTaxiMarkerRestore(
        attempt: attempt,
        reason: 'self_heal_$reason',
      );
    } catch (_) {
      success = false;
    }
    if (success) {
      _markerLifecycle.noteSelfHealSucceeded(DateTime.now());
      _logNavR12Marker(
        event: 'self_heal_success',
        selfHealReason: reason,
        recreateAttempt: attempt,
      );
      await _syncMapboxUserLocationPuckVisibility();
    } else {
      _markerLifecycle.noteSelfHealFailed(reason, DateTime.now());
      _logNavR12Marker(
        event: 'self_heal_failed',
        selfHealReason: reason,
        recreateAttempt: attempt,
      );
      _scheduleMarkerSelfHeal(reason);
    }
  }

  /// NAV-R12-D: fast, coalesced marker update on a fresh GPS fix. Never
  /// blocks the caller; if a native update is already in flight the newest
  /// fix simply replaces the pending one (last-wins).
  void _scheduleDriverMarkerFastUpdate(geo.Position pos) {
    _pendingMarkerUpdatePos = pos;
    if (_driverPointManager == null &&
        !(_markerSelfHealTimer?.isActive ?? false) &&
        !_mapStyleChanging &&
        _map != null) {
      _markerLifecycle.noteFailure('manager_missing_on_fix', DateTime.now());
      _scheduleMarkerSelfHeal('manager_missing_on_fix');
    }
    if (!_markerLifecycle.beginUpdate(DateTime.now())) {
      _logNavR12Marker(event: 'skipped_in_flight');
      return;
    }
    unawaited(_runCoalescedMarkerUpdate());
  }

  Future<void> _runCoalescedMarkerUpdate() async {
    var runNext = true;
    while (runNext && mounted) {
      final pos = _pendingMarkerUpdatePos;
      var applied = false;
      if (pos != null) {
        try {
          applied = await _updateDriverMarker(pos);
        } catch (_) {
          applied = false;
        }
      }
      runNext = _markerLifecycle.finishUpdate(
        applied: applied,
        now: DateTime.now(),
      );
      if (runNext) {
        _markerLifecycle.beginUpdate(DateTime.now());
      }
    }
  }

  Future<void> _disposeDriverPointAnnotationManager() async {
    final map = _map;
    final mgr = _driverPointManager;
    if (mgr != null) {
      try {
        if (map != null) {
          await map.annotations.removeAnnotationManager(mgr);
        } else {
          await mgr.deleteAll();
        }
      } catch (_) {
        try {
          await mgr.deleteAll();
        } catch (_) {}
      }
    }
    _driverPointManager = null;
    _driverMarker = null;
    _driverMarkerUsesTaxiAsset = false;
    debugPrint('[NAV_MARKER] lifecycle=driver_manager_disposed');
  }

  /// NAV-R12-I-A / NAV-R13: rotation alignment stays MAP so the taxi nose
  /// follows compass bearings/road direction (Mapbox's default `auto`
  /// resolves to viewport for point annotations, which broke the nose under
  /// a bearing-rotated camera). Pitch alignment is VIEWPORT so the sprite
  /// keeps its on-screen size instead of foreshortening/shrinking under the
  /// pitched follow camera (field feedback NAV-R13).
  /// Applies to the driver/taxi manager only; pins keep plugin defaults.
  Future<void> _configureDriverPointManagerForTaxiMarker(
    mb.PointAnnotationManager mgr,
  ) async {
    var event = 'manager_configured';
    String? failReason;
    try {
      await mgr.setIconRotationAlignment(mb.IconRotationAlignment.MAP);
      await mgr.setIconPitchAlignment(mb.IconPitchAlignment.VIEWPORT);
    } catch (e) {
      event = 'manager_config_failed';
      failReason = e.runtimeType.toString();
    }
    _logNavBounded(
      'NAV_R13_MARKER_VISUAL',
      'markerUpdate=$event rotationAlignment=map pitchAlignment=viewport'
          '${failReason != null ? ' reason=$failReason' : ''}',
      intervalMs: 1,
    );
    unawaited(
      NavDiagnosticsRecorder.instance.recordNavEngineEvent(
        tag: 'NAV_R13_MARKER_VISUAL',
        fields: <String, dynamic>{
          'event': event,
          'rotationAlignment': 'map',
          'pitchAlignment': 'viewport',
          if (failReason != null) 'reason': failReason,
        },
      ),
    );
  }

  Future<void> _recreateAnnotationManagers() async {
    if (_map == null) return;
    await _syncMapboxUserLocationPuckVisibility();
    await _disposeDriverPointAnnotationManager();
    _routeLineManager = await _map!.annotations
        .createPolylineAnnotationManager();
    _pinsPointManager = await _map!.annotations.createPointAnnotationManager();
    final driverMgr = await _map!.annotations.createPointAnnotationManager();
    await _configureDriverPointManagerForTaxiMarker(driverMgr);
    _driverPointManager = driverMgr;
    await _syncMapboxUserLocationPuckVisibility();
  }

  MapThemeMode _effectiveMapThemeFor(_CameraMode mode) {
    return _mapThemeOverride ??
        (mode == _CameraMode.follow ? MapThemeMode.light : MapThemeMode.dark);
  }

  String _styleForTheme(MapThemeMode theme) {
    return driverMapStyleForTheme(
      isLightTheme: theme == MapThemeMode.light,
      visualMode: _driverMapVisualMode,
    );
  }

  String _styleForMode(_CameraMode mode) {
    return _styleForTheme(_effectiveMapThemeFor(mode));
  }

  Future<void> _applyMapStyleForMode() async {
    if (_map == null) return;
    final theme = _effectiveMapThemeFor(_cameraMode);
    final target = _styleForMode(_cameraMode);
    debugPrint(
      '[MAP][STYLE_REQ] theme=${theme == MapThemeMode.light ? 'light' : 'dark'} target=$target active=$_activeMapStyleUri pending=${_pendingMapStyleUri ?? ''}',
    );
    if (_activeMapStyleUri == target) {
      debugPrint('[MAP][STYLE_SKIP] reason=already_active target=$target');
      await applyDriverMapVisualClarity(
        style: _map!.style,
        visualMode: _driverMapVisualMode,
      );
      return;
    }
    if (_pendingMapStyleUri == target) {
      debugPrint('[MAP][STYLE_SKIP] reason=in_flight target=$target');
      return;
    }
    _pendingMapStyleUri = target;
    _mapStyleChanging = true;
    debugPrint(
      '[NAV_MAPSTYLE] switching=${driverMapVisualModeLogLabel(_driverMapVisualMode)} target=$target',
    );
    debugPrint('[NAV_MARKER] paused_for_style_change');
    unawaited(
      NavDiagnosticsRecorder.instance.recordMapStyleChange(
        mode: driverMapVisualModeLogLabel(_driverMapVisualMode),
        phase: 'started',
      ),
    );
    try {
      // NAV-UI-R6E: capture last taxi visual BEFORE the style swap and keep
      // the visible marker alive until the style itself replaces it; the
      // manager is disposed after setStyleURI so there is no early blank gap.
      _captureTaxiVisualSnapshotForStyleSwap();
      debugPrint(
        '[MAP_THEME] selected=${theme == MapThemeMode.light ? 'light' : 'dark'} style=$target',
      );
      await _map!.style.setStyleURI(target);
      _activeMapStyleUri = target;
      await _disposeDriverPointAnnotationManager();
      await applyDriverMapVisualClarity(
        style: _map!.style,
        visualMode: _driverMapVisualMode,
      );
      _logNavMapStyle(reason: 'style_applied');
      _mapRedrawCountThisMinute += 1;
      await _syncMapboxUserLocationPuckVisibility();
      await _recreateAnnotationManagers();
      _driverMarkerUsesTaxiAsset = false;
      _pickupPin = null;
      _dropoffPin = null;
      _routeLine = null;
      _routeLineOutline = null;
      _routeLineCompleted = null;
      // Managers are ready again: unblock marker updates BEFORE the restore,
      // otherwise the restore is a no-op and the taxi vanishes until the next
      // GPS callback (NAV-UI-R6E root cause).
      _mapStyleChanging = false;
      final restore = await _restoreDriverVisualsAfterStyleChange(
        reason: 'style_swap',
      );
      // NAV-R12-D: clear degraded state only once the marker actually
      // exists again after the style swap.
      if (restore.taxi && _driverMarker != null) {
        _markerLifecycle.noteSelfHealSucceeded(DateTime.now());
      }
      _scheduleTaxiMarkerRestoreRetries(reason: 'style_swap');
      await _syncMapboxUserLocationPuckVisibility();
      debugPrint(
        '[NAV_UI_R6D_STYLE_RESTORE] route=${restore.route} taxi=${restore.taxi} reason=style_swap',
      );
      debugPrint('[NAV_MARKER] recreated_after_style');
      unawaited(
        NavDiagnosticsRecorder.instance.recordMapStyleChange(
          mode: driverMapVisualModeLogLabel(_driverMapVisualMode),
          phase: 'completed',
        ),
      );
      debugPrint(
        '[MAP_THEME] redraw route=${restore.route} marker=${restore.taxi} pins=${_routeCoords.length >= 2}',
      );
      debugPrint('[MAP][STYLE_DONE] target=$target');
    } catch (e) {
      debugPrint('[MAP][STYLE_SKIP] reason=error target=$target error=$e');
      unawaited(
        NavDiagnosticsRecorder.instance.recordMapStyleChange(
          mode: driverMapVisualModeLogLabel(_driverMapVisualMode),
          phase: 'failed',
          error: e.toString(),
        ),
      );
      unawaited(
        NavDiagnosticsRecorder.instance.recordException(
          context: 'map_style_change',
          error: e,
        ),
      );
    } finally {
      _mapStyleChanging = false;
      if (_pendingMapStyleUri == target) {
        _pendingMapStyleUri = null;
      }
    }
  }

  Future<void> _setMapTheme(MapThemeMode theme) async {
    if (!mounted) return;
    setState(() => _mapThemeOverride = theme);
    await _applyMapStyleForMode();
  }

  /// Restore route line + taxi marker immediately after a style change or
  /// annotation-manager recreation. Uses the last known visual position (nav
  /// interpolator, GPS, or route start) so the driver never sees a bare map
  /// while waiting 3–4 seconds for the next GPS callback.
  Future<({bool route, bool taxi})> _restoreDriverVisualsAfterStyleChange({
    required String reason,
  }) async {
    var restoredRoute = false;

    if (_routeCoords.length >= 2) {
      try {
        await _drawRouteLine(_routeCoords, force: true);
        await _drawPins(_routeCoords.first, _routeCoords.last);
        restoredRoute = true;
      } catch (_) {
        restoredRoute = false;
      }
    }

    final restoredTaxi = await _attemptTaxiMarkerRestore(
      attempt: 0,
      reason: reason,
    );

    if (_lastPos != null) {
      try {
        _updateRouteSnapState(_lastPos!);
        await _syncVisibleRouteLineWithProgress(
          _lastPos!,
          reason: 'style_restore',
        );
      } catch (_) {}
    }

    unawaited(
      NavDiagnosticsRecorder.instance.recordNavEngineEvent(
        tag: 'NAV_UI_R6D_STYLE_RESTORE',
        fields: <String, dynamic>{
          'route': restoredRoute,
          'taxi': restoredTaxi || _driverMarker != null,
          'reason': reason,
          'hasGps': _lastPos != null,
        },
      ),
    );

    return (route: restoredRoute, taxi: restoredTaxi || _driverMarker != null);
  }

  /// NAV-UI-R6E: snapshot the currently visible taxi marker (interpolated
  /// visual, marker geometry, GPS, or route head) before the style is swapped.
  void _captureTaxiVisualSnapshotForStyleSwap() {
    if (_navR3VisualLat != null && _navR3VisualLon != null) {
      _taxiVisualSnapshotForStyleSwap = (
        lat: _navR3VisualLat!,
        lon: _navR3VisualLon!,
        bearing: _navR3VisualBearing,
        source: 'snapshot',
      );
      return;
    }
    final marker = _driverMarker;
    if (marker != null) {
      final coords = marker.geometry.coordinates;
      _taxiVisualSnapshotForStyleSwap = (
        lat: coords.lat.toDouble(),
        lon: coords.lng.toDouble(),
        bearing:
            marker.iconRotate ??
            (_lastKnownBearing.isFinite ? _lastKnownBearing : 0.0),
        source: 'snapshot',
      );
      return;
    }
    _taxiVisualSnapshotForStyleSwap = null;
  }

  /// Best-effort taxi visual for restore: style-swap snapshot > live nav
  /// visual > last GPS fix > route start.
  ({double lat, double lon, double bearing, String source})?
  _lastKnownTaxiVisualForRestore() {
    final snapshot = _taxiVisualSnapshotForStyleSwap;
    if (snapshot != null) return snapshot;
    if (_navR3VisualLat != null && _navR3VisualLon != null) {
      return (
        lat: _navR3VisualLat!,
        lon: _navR3VisualLon!,
        bearing: _navR3VisualBearing,
        source: 'snapshot',
      );
    }
    final pos = _lastPos;
    if (pos != null) {
      return (
        lat: pos.latitude,
        lon: pos.longitude,
        bearing: _lastKnownBearing.isFinite ? _lastKnownBearing : 0.0,
        source: 'last_pos',
      );
    }
    if (_routeCoords.length >= 2) {
      final head = _routeCoords.first;
      return (
        lat: head.lat,
        lon: head.lon,
        bearing: _lastKnownBearing.isFinite ? _lastKnownBearing : 0.0,
        source: 'route_start',
      );
    }
    return null;
  }

  /// NAV-UI-R6E: create the taxi marker (fallback icon instantly if the PNG is
  /// not ready — `_createDriverMarkerAnnotation` handles that swap) from the
  /// best known visual, without waiting for a GPS callback.
  Future<bool> _attemptTaxiMarkerRestore({
    required int attempt,
    required String reason,
  }) async {
    if (_driverMarker != null) return true;
    final visual = _lastKnownTaxiVisualForRestore();
    final source = visual?.source ?? 'fallback';
    var success = false;
    if (visual != null && _map != null && !_mapStyleChanging) {
      try {
        var mgr = _driverPointManager;
        if (mgr == null) {
          mgr = await _map!.annotations.createPointAnnotationManager();
          await _configureDriverPointManagerForTaxiMarker(mgr);
          _driverPointManager = mgr;
        }
        _driverMarker = await _createDriverMarkerAnnotation(
          mgr: mgr,
          geometry: _mbPoint(visual.lon, visual.lat),
          markerBearing: visual.bearing,
        );
        success = _driverMarker != null;
        if (success) {
          // NAV-R12-D: a freshly created marker proves the manager works.
          _markerLifecycle.noteSelfHealSucceeded(DateTime.now());
        }
      } catch (e) {
        if (_isMapboxAnnotationManagerLost(e)) {
          _resetDriverMarkerOnNativeError('taxi_restore_attempt$attempt');
        }
      }
    }
    debugPrint(
      '[NAV_UI_R6E_TAXI_RESTORE] attempt=$attempt success=$success source=$source reason=$reason',
    );
    unawaited(
      NavDiagnosticsRecorder.instance.recordNavEngineEvent(
        tag: 'NAV_UI_R6E_TAXI_RESTORE',
        fields: <String, dynamic>{
          'attempt': attempt,
          'success': success,
          'source': source,
          'reason': reason,
        },
      ),
    );
    return success;
  }

  /// NAV-UI-R6E: retry marker restore at 100/300/700 ms after style load in
  /// case the immediate restore raced native style loading. Also upgrades a
  /// temporary fallback marker to the taxi PNG once the asset is available.
  /// Each attempt re-forces the puck hidden.
  void _scheduleTaxiMarkerRestoreRetries({required String reason}) {
    for (final entry in const <(int, int)>[(1, 100), (2, 300), (3, 700)]) {
      final (attempt, delayMs) = entry;
      Future<void>.delayed(Duration(milliseconds: delayMs), () async {
        if (!mounted || _map == null || _mapStyleChanging) return;
        if (_driverMarker == null) {
          await _attemptTaxiMarkerRestore(attempt: attempt, reason: reason);
        } else if (!_driverMarkerUsesTaxiAsset && _driverTaxiMarkerAvailable) {
          await _upgradeFallbackMarkerToTaxi(attempt: attempt, reason: reason);
        }
        await _syncMapboxUserLocationPuckVisibility();
      });
    }
  }

  /// Replace a temporary fallback marker with the taxi PNG in place.
  Future<void> _upgradeFallbackMarkerToTaxi({
    required int attempt,
    required String reason,
  }) async {
    final mgr = _driverPointManager;
    final marker = _driverMarker;
    if (mgr == null || marker == null) return;
    final geometry = marker.geometry;
    final bearing =
        marker.iconRotate ??
        (_lastKnownBearing.isFinite ? _lastKnownBearing : 0.0);
    try {
      await mgr.delete(marker);
      _driverMarker = null;
      _driverMarker = await _createDriverMarkerAnnotation(
        mgr: mgr,
        geometry: geometry,
        markerBearing: bearing,
      );
      debugPrint(
        '[NAV_UI_R6E_TAXI_RESTORE] attempt=$attempt success=${_driverMarker != null} source=fallback reason=${reason}_asset_upgrade',
      );
    } catch (e) {
      if (_isMapboxAnnotationManagerLost(e)) {
        _resetDriverMarkerOnNativeError('taxi_asset_upgrade');
      }
    }
  }

  void _logNavMapStyle({required String reason}) {
    _logNavBounded(
      'NAV_MAPSTYLE',
      'mode=${driverMapVisualModeLogLabel(_driverMapVisualMode)} reason=$reason',
      intervalMs: reason == 'user_toggle' ? 1 : 2500,
    );
  }

  ({
    NavR9OfflineUiState state,
    String reason,
    bool showTunnelChip,
    bool showGpsReacquireChip,
  })
  _navR9OfflineReadiness() {
    final prediction = _lastNavMotionPrediction;
    return NavR9OfflineReadiness.derive(
      liveRideActive: _liveRideActive,
      followNavActive: _cameraMode == _CameraMode.follow,
      localRouteReady: _routeCoords.length >= 2,
      predictionActive: prediction?.predictionActive ?? false,
      predictionConfidence: prediction?.confidence,
      weakGps: _isWeakGpsForPrediction(_lastPos),
      gapSinceLastEngineMs: _gapSinceLastNavEngineMs(),
    );
  }

  void _logNavR9Offline({
    required NavR9OfflineUiState state,
    required String reason,
  }) {
    _logNavBounded(
      'NAV_R9_OFFLINE',
      'state=${NavR9OfflineReadiness.logStateLabel(state)} reason=$reason',
      intervalMs: 2500,
    );
    _recordNavDiagR9OfflineTransition(state: state, reason: reason);
  }

  Widget _buildNavR9DataOffStatusChip({
    required bool showTunnelChip,
    required bool showGpsReacquireChip,
    required Color navText,
    required Color navSurface,
    required Color navAccent,
  }) {
    if (!showTunnelChip && !showGpsReacquireChip) {
      return const SizedBox.shrink();
    }
    final label = showGpsReacquireChip
        ? _tr(
            nl: 'GPS wordt opnieuw gezocht',
            en: 'Reacquiring GPS',
            fr: 'Reacquisition GPS',
            es: 'Readquiriendo GPS',
          )
        : _tr(
            nl: 'Tunnel/offline begeleiding',
            en: 'Tunnel/offline guidance',
            fr: 'Guidage tunnel/hors ligne',
            es: 'Guia tunel/sin conexion',
          );
    final icon = showGpsReacquireChip
        ? Icons.gps_not_fixed_rounded
        : Icons.wifi_off_rounded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: navSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: navAccent.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: navAccent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: navText.withOpacity(0.92),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleDriverMapVisualMode() async {
    if (!kDriverMapSatelliteToggleEnabled || _map == null) return;
    final next = _driverMapVisualMode == DriverMapVisualMode.street
        ? DriverMapVisualMode.satellite
        : DriverMapVisualMode.street;
    if (mounted) {
      setState(() => _driverMapVisualMode = next);
    } else {
      _driverMapVisualMode = next;
    }
    _logNavMapStyle(reason: 'user_toggle');
    await _applyMapStyleForMode();
  }

  double _driverTaxiIconSizeForCurrentZoom() {
    return driverTaxiMarkerIconSizeForZoom(_lastMapCameraZoom);
  }

  Future<void> _syncDriverMarkerIconSizeForZoom() async {
    if (!_canUpdateDriverMarker) return;
    final mgr = _driverPointManager;
    final marker = _driverMarker;
    if (mgr == null || marker == null) return;
    final size = _driverMarkerUsesTaxiAsset
        ? _driverTaxiIconSizeForCurrentZoom()
        : driverFallbackMarkerIconSizeForZoom(_lastMapCameraZoom);
    final current = marker.iconSize ?? 0.0;
    if ((current - size).abs() < 0.03) return;
    marker.iconSize = size;
    try {
      await mgr.update(marker);
    } catch (e) {
      if (_isMapboxAnnotationManagerLost(e)) {
        _resetDriverMarkerOnNativeError('sync_icon_size');
      }
    }
  }

  mb.Point _mbPoint(double lon, double lat) =>
      mb.Point(coordinates: mb.Position(lon, lat));

  double _metersBetween(_LonLat a, _LonLat b) {
    return driverMetersBetween(a, b);
  }

  double _snapThresholdFor(geo.Position pos) {
    final accuracy = pos.accuracy.isFinite && pos.accuracy > 0
        ? pos.accuracy
        : 20.0;
    return math.max(35.0, math.min(90.0, accuracy * 1.8));
  }

  double _speedKmhFor(geo.Position pos) {
    if (!pos.speed.isFinite || pos.speed < 0) return 0.0;
    return pos.speed * 3.6;
  }

  double? _gpsFixAgeSec(geo.Position pos) {
    final ts = pos.timestamp;
    return DateTime.now().difference(ts).inMilliseconds / 1000.0;
  }

  bool _isGpsQualityAcceptableForCamera(geo.Position pos) {
    final ageSec = _gpsFixAgeSec(pos);
    if (ageSec != null && ageSec > _followCameraStaleGpsMaxAgeSec) {
      return false;
    }
    final accuracy = pos.accuracy;
    if (accuracy.isFinite && accuracy > _followCameraPoorAccuracyM) {
      return false;
    }
    return true;
  }

  int _followCameraThrottleMsFor(geo.Position pos) {
    final speedKmh = _speedKmhFor(pos);
    if (speedKmh >= 25) return 160;
    if (speedKmh >= 8) return 200;
    return 260;
  }

  int _followCameraAnimMsFor(geo.Position pos) {
    final speedKmh = _speedKmhFor(pos);
    if (speedKmh >= 30) return 140;
    if (speedKmh >= 10) return 180;
    return 220;
  }

  ({double zoom, double pitch, String reason}) _followCameraZoomPitchFor(
    geo.Position pos,
  ) {
    final speedKmh = _speedKmhFor(pos);
    final distanceToManeuver =
        _navInstructionSnapshot?.distanceToManeuverMeters ??
        _nextNavDistanceM ??
        double.infinity;
    final nearManeuver =
        distanceToManeuver.isFinite &&
        distanceToManeuver <= kDriverNavR1NearManeuverCameraDistanceM;

    if (nearManeuver) {
      if (speedKmh < 4) {
        return (zoom: 17.4, pitch: 56.0, reason: 'near_maneuver');
      }
      if (speedKmh < 15) {
        return (zoom: 17.8, pitch: 62.0, reason: 'near_maneuver');
      }
      return (zoom: 18.1, pitch: 66.0, reason: 'near_maneuver');
    }

    // NAV-R1: reduced default follow zoom (was ~18.0–18.9).
    if (speedKmh < 4) {
      return (zoom: 16.4, pitch: 50.0, reason: 'normal_follow');
    }
    if (speedKmh < 15) {
      return (zoom: 16.9, pitch: 56.0, reason: 'normal_follow');
    }
    return (zoom: 17.2, pitch: 60.0, reason: 'normal_follow');
  }

  double _normalizeBearingDeg(double bearing) {
    var b = bearing % 360.0;
    if (b < 0) b += 360.0;
    return b;
  }

  double _smoothFollowCameraBearing(
    double target,
    double speedKmh, {
    double bearingModeWeight = 1.0,
  }) {
    final normalizedTarget = _normalizeBearingDeg(target);
    final prev = _lastSmoothedCameraBearing;
    if (prev == null || !prev.isFinite) {
      _lastSmoothedCameraBearing = normalizedTarget;
      return normalizedTarget;
    }
    var delta = normalizedTarget - prev;
    while (delta > 180) delta -= 360;
    while (delta < -180) delta += 360;
    final weight = bearingModeWeight.clamp(0.0, 1.0);
    final maxStep =
        (speedKmh < 4 ? 3.5 : (speedKmh < 20 ? 14.0 : 28.0)) * weight;
    if (maxStep <= 0.01) {
      return prev;
    }
    if (delta.abs() <= maxStep) {
      _lastSmoothedCameraBearing = normalizedTarget;
      return normalizedTarget;
    }
    final next = _normalizeBearingDeg(prev + delta.sign * maxStep);
    _lastSmoothedCameraBearing = next;
    return next;
  }

  void _logNavBounded(String tag, String message, {int intervalMs = 900}) {
    final now = DateTime.now();
    final last = _lastNavDebugAt[tag];
    if (last != null && now.difference(last).inMilliseconds < intervalMs)
      return;
    _lastNavDebugAt[tag] = now;
    debugPrint('[$tag] $message');
  }

  void _syncNavDiagSession() {
    if (_isActiveDriverNavEngineContext()) {
      unawaited(
        NavDiagnosticsRecorder.instance.beginSessionIfNeeded(
          trigger: 'follow_nav',
        ),
      );
    } else {
      unawaited(
        NavDiagnosticsRecorder.instance.endSessionIfActive(
          reason: 'nav_context_end',
        ),
      );
    }
  }

  void _recordNavDiagGpsUpdate(
    geo.Position pos,
    geo.Position? prev, {
    double? metersFromPrev,
  }) {
    if (!NavDiagnosticsRecorder.instance.hasActiveSession) return;
    final now = DateTime.now();
    final last = _lastNavDiagGpsAt;
    final dtMs = last == null ? 0 : now.difference(last).inMilliseconds;
    _lastNavDiagGpsAt = now;
    final distanceFromLastM =
        metersFromPrev != null && metersFromPrev.isFinite && metersFromPrev > 0
        ? metersFromPrev
        : null;
    unawaited(
      NavDiagnosticsRecorder.instance.recordGpsUpdate(
        dtMs: dtMs,
        speedKmh: _speedKmhFor(pos),
        accuracyM: pos.accuracy.isFinite && pos.accuracy > 0
            ? pos.accuracy
            : -1,
        heading: pos.heading.isFinite && pos.heading >= 0 ? pos.heading : null,
        distanceFromLastM: distanceFromLastM,
      ),
    );
  }

  void _recordNavDiagR9OfflineTransition({
    required NavR9OfflineUiState state,
    required String reason,
  }) {
    final prev = _lastNavDiagR9State;
    _lastNavDiagR9State = state;
    if (prev == state) return;
    final now = DateTime.now();
    if (state == NavR9OfflineUiState.prediction ||
        state == NavR9OfflineUiState.gpsReacquire) {
      _lastNavDiagR9EnteredAt = now;
      unawaited(
        NavDiagnosticsRecorder.instance.recordOfflineMode(
          transition: 'entered',
          reason: reason,
          state: NavR9OfflineReadiness.logStateLabel(state),
        ),
      );
      return;
    }
    if (prev == NavR9OfflineUiState.prediction ||
        prev == NavR9OfflineUiState.gpsReacquire) {
      final entered = _lastNavDiagR9EnteredAt;
      final durationMs = entered == null
          ? null
          : now.difference(entered).inMilliseconds;
      _lastNavDiagR9EnteredAt = null;
      unawaited(
        NavDiagnosticsRecorder.instance.recordOfflineMode(
          transition: 'exited',
          reason: reason,
          durationMs: durationMs,
          state: prev == null
              ? null
              : NavR9OfflineReadiness.logStateLabel(prev),
        ),
      );
    }
  }

  Future<void> _shareNavDiagnostics() async {
    try {
      final file = await NavDiagnosticsRecorder.instance.exportLatestSessions(
        count: 2,
        asText: false,
      );
      if (file == null) {
        _toast(
          _tr(
            nl: 'Geen navigatie-diagnose beschikbaar.',
            en: 'No navigation diagnostics available.',
            fr: 'Aucun diagnostic de navigation disponible.',
            es: 'No hay diagnostico de navegacion disponible.',
          ),
        );
        return;
      }
      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        subject: 'Fluxidi navigatie-diagnose',
        text: _tr(
          nl: 'Fluxidi navigatie-diagnose (geen PII).',
          en: 'Fluxidi navigation diagnostics (no PII).',
          fr: 'Diagnostic navigation Fluxidi (sans PII).',
          es: 'Diagnostico de navegacion Fluxidi (sin PII).',
        ),
      );
    } catch (e) {
      unawaited(
        NavDiagnosticsRecorder.instance.recordException(
          context: 'share_nav_diag',
          error: e,
        ),
      );
      _toast(
        _tr(
          nl: 'Diagnose delen mislukt.',
          en: 'Could not share diagnostics.',
          fr: 'Partage du diagnostic impossible.',
          es: 'No se pudo compartir el diagnostico.',
        ),
      );
    }
  }

  ({double enterThresholdM, double exitThresholdM}) _matchThresholdsFor(
    geo.Position pos,
  ) {
    final base = _snapThresholdFor(pos);
    final speedKmh = _speedKmhFor(pos);
    final navAgeSec = _trackingStartedAt == null
        ? 999.0
        : DateTime.now().difference(_trackingStartedAt!).inMilliseconds /
              1000.0;
    final justStarted = navAgeSec <= 18.0;
    final movingFast = speedKmh >= 35.0;
    final enter = justStarted
        ? math.max(base, 70.0)
        : (movingFast ? math.max(base, 48.0) : base);
    final exit = enter + 18.0;
    return (enterThresholdM: enter, exitThresholdM: exit);
  }

  bool _isProgressPlausible(_RouteSnap snap, geo.Position pos) {
    final prev = _lastVisualProgressM;
    if (prev == null) return true;
    final speedKmh = _speedKmhFor(pos);
    final backwardToleranceM = speedKmh < 6.0 ? 35.0 : 22.0;
    if (snap.distanceAlongRouteM < prev - backwardToleranceM) {
      return false;
    }
    final maxForwardJumpM = math.max(70.0, speedKmh * 2.8 + 38.0);
    if (snap.distanceAlongRouteM > prev + maxForwardJumpM) {
      return false;
    }
    return true;
  }

  bool _canSnapToRoute(geo.Position pos, _RouteSnap? snap) {
    if (snap == null) return false;
    final thresholds = _matchThresholdsFor(pos);
    final threshold = _useMatchedVisual
        ? thresholds.exitThresholdM
        : thresholds.enterThresholdM;
    if (snap.distanceFromRouteM > threshold) return false;
    return _isProgressPlausible(snap, pos);
  }

  _RouteSnap? _snapToRouteOn(List<_LonLat> routeCoords, _LonLat raw) {
    return driverSnapToRouteOn(routeCoords, raw);
  }

  _RouteSnap? _snapToRoute(_LonLat raw) => _snapToRouteOn(_routeCoords, raw);

  double _distanceAlongRouteFor(_LonLat point) {
    return _snapToRoute(point)?.distanceAlongRouteM ?? 0.0;
  }

  double _distanceAlongRouteForCoords(
    List<_LonLat> routeCoords,
    _LonLat point,
  ) {
    return driverDistanceAlongRouteForCoords(routeCoords, point);
  }

  void _resetNavRouteProgressState() {
    _driverNavRouteProgress.reset();
    _lastNavRouteProgress = null;
    _navRouteProgressRouteFingerprint = null;
  }

  void _resetNavCameraPolicyState() {
    _driverNavCameraPolicy.reset();
    _lastNavCameraPolicy = null;
  }

  void _resetNavConfidenceState() {
    _driverNavConfidenceEngine.reset();
    _lastNavConfidence = null;
  }

  void _resetNavComplexityState() {
    _navComplexityMonitor.reset();
    _lastNavCautionState = NavCautionState.inactive;
    _lastNavR14ComplexitySignature = null;
  }

  NavComplexityMonitorInput _buildNavComplexityMonitorInput(geo.Position pos) {
    final progress = _lastNavRouteProgress;
    final confidence = _lastNavConfidence;
    final prediction = _lastNavMotionPrediction;
    return NavComplexityMonitorInput(
      timestamp: DateTime.now(),
      liveRideActive: _liveRideActive,
      followMode: _cameraMode == _CameraMode.follow,
      overallConfidence: confidence?.overallScore,
      trustInstruction: confidence?.trustInstruction ?? true,
      trustBearing: confidence?.trustBearing ?? true,
      snapDistanceM: progress?.snapDistanceM,
      offRouteLikely: progress?.offRouteLikely ?? _offRouteLikely,
      reroutePending: _isRerouting,
      headingDeltaDeg: progress?.headingDeltaDeg ?? _navHeadingDeltaDegFor(pos),
      predictionActive: prediction?.predictionActive ?? false,
      gapBridgeMs: _gapSinceLastNavEngineMs(),
      maneuverModifier: _nextNavModifier,
      instructionStepIndex: _nextStepIndex,
      speedKmh: _speedKmhFor(pos),
      distanceToManeuverM:
          _navInstructionSnapshot?.distanceToManeuverMeters ??
          _nextNavDistanceM,
      maneuverType: _nextNavType,
    );
  }

  void _updateNavComplexityForPosition(geo.Position pos) {
    if (!_isActiveDriverNavEngineContext()) {
      final wasShowing = _lastNavCautionState.shouldShowCaution;
      _resetNavComplexityState();
      if (wasShowing && mounted) setState(() {});
      return;
    }
    final prevShowing = _lastNavCautionState.shouldShowCaution;
    final state = _navComplexityMonitor.update(
      _buildNavComplexityMonitorInput(pos),
    );
    _lastNavCautionState = state;
    _logNavR14Complexity(state);
    if (prevShowing != state.shouldShowCaution && mounted) {
      setState(() {});
    }
  }

  void _logNavR14Complexity(NavCautionState state) {
    final confidence = _lastNavConfidence;
    final progress = _lastNavRouteProgress;
    final snapBucket = NavComplexityMonitor.snapDistanceBucket(
      progress?.snapDistanceM,
    );
    final signature =
        '${state.shouldShowCaution}|${state.reasonCode}|${state.signalCount}|'
        '${confidence?.overallScore.round() ?? -1}|$snapBucket';
    final changed = signature != _lastNavR14ComplexitySignature;
    _lastNavR14ComplexitySignature = signature;
    _logNavBounded(
      'NAV_R14_COMPLEXITY',
      'active=${state.shouldShowCaution} '
          'severity=${state.severity.name} '
          'reason=${state.reasonCode} '
          'signals=${state.signalCount} '
          'confidence=${confidence?.overallScore.round() ?? -1} '
          'snapDistBucket=$snapBucket '
          'trustBearing=${confidence?.trustBearing ?? true} '
          'trustInstruction=${confidence?.trustInstruction ?? true}',
      intervalMs: changed ? 1 : 3000,
    );
    if (changed) {
      unawaited(
        NavDiagnosticsRecorder.instance.recordNavEngineEvent(
          tag: 'NAV_R14_COMPLEXITY',
          fields: <String, dynamic>{
            'active': state.shouldShowCaution,
            'severity': state.severity.name,
            'reason': state.reasonCode,
            'confidence': confidence?.overallScore.round(),
            'snapDistBucket': snapBucket,
            'trustBearing': confidence?.trustBearing,
            'trustInstruction': confidence?.trustInstruction,
            'signals': state.signalCount,
          },
        ),
      );
    }
  }

  void _resetNavMotionPredictionState() {
    _driverNavMotionPrediction.reset();
    _lastNavMotionPrediction = null;
  }

  void _resetNavInstructionPolicyState() {
    _driverNavInstructionPolicy.reset();
  }

  int _gapSinceLastNavEngineMs() {
    final output = _lastNavEngineOutput;
    if (output == null) return 0;
    return DateTime.now()
        .difference(output.timestamp)
        .inMilliseconds
        .clamp(0, 600000);
  }

  double? _navHeadingDeltaDegFor(geo.Position pos) {
    final rawHeading = pos.heading.isFinite && pos.heading >= 0
        ? pos.heading
        : null;
    if (rawHeading == null) return null;
    final progress = _lastNavRouteProgress;
    final routeBearing =
        _routeBearingFromProgress(progress) ??
        _routeBearingAtSnap(_lastRouteSnap);
    if (routeBearing == null || !routeBearing.isFinite) return null;
    var delta = (rawHeading - routeBearing) % 360.0;
    if (delta > 180.0) delta -= 360.0;
    if (delta < -180.0) delta += 360.0;
    return delta.abs();
  }

  NavConfidenceInput _buildNavConfidenceInput(geo.Position pos) {
    final progress = _lastNavRouteProgress;
    return NavConfidenceInput(
      timestamp: pos.timestamp,
      gpsAccuracyM: pos.accuracy.isFinite && pos.accuracy > 0
          ? pos.accuracy
          : null,
      speedKmh: _speedKmhFor(pos),
      routeConfidence: progress?.confidence,
      snapDistanceM: progress?.snapDistanceM,
      hasReliableSnap: progress?.hasReliableSnap ?? false,
      offRouteLikely: progress?.offRouteLikely ?? _offRouteLikely,
      forwardProgress: progress?.forwardProgress ?? true,
      headingDeltaDeg: _navHeadingDeltaDegFor(pos),
      liveRideActive: _liveRideActive,
    );
  }

  void _updateNavConfidenceForPosition(geo.Position pos) {
    if (!_isActiveDriverNavEngineContext()) {
      _lastNavConfidence = null;
      return;
    }
    try {
      final output = _driverNavConfidenceEngine.update(
        _buildNavConfidenceInput(pos),
      );
      _lastNavConfidence = output;
      _logNavBounded(
        'NAV_R6_CONFIDENCE',
        'overall=${output.overallScore.round()} '
            'gps=${output.gpsScore.round()} '
            'route=${output.routeScore.round()} '
            'heading=${output.headingScore.round()} '
            'motion=${output.motionScore.round()} '
            'camera=${output.cameraScore.round()} '
            'instruction=${output.instructionScore.round()} '
            'trustSnap=${output.trustRouteSnap} '
            'trustBearing=${output.trustBearing} '
            'trustInstruction=${output.trustInstruction} '
            'reason=${output.reason}',
        intervalMs: 1500,
      );
      unawaited(
        NavDiagnosticsRecorder.instance.recordNavEngineEvent(
          tag: 'NAV_R6_CONFIDENCE',
          fields: <String, dynamic>{
            'overall': output.overallScore.round(),
            'gps': output.gpsScore.round(),
            'route': output.routeScore.round(),
            'heading': output.headingScore.round(),
            'motion': output.motionScore.round(),
            'camera': output.cameraScore.round(),
            'instruction': output.instructionScore.round(),
            'trustSnap': output.trustRouteSnap,
            'trustBearing': output.trustBearing,
            'trustInstruction': output.trustInstruction,
            'reason': output.reason,
          },
        ),
      );
    } catch (_) {
      _lastNavConfidence = null;
    }
    _updateNavComplexityForPosition(pos);
  }

  NavCameraPolicyInput _buildNavCameraPolicyInput(
    geo.Position pos, {
    required bool manualRecenter,
  }) {
    final distanceToManeuver =
        _navInstructionSnapshot?.distanceToManeuverMeters ?? _nextNavDistanceM;
    final nearManeuver =
        distanceToManeuver != null &&
        distanceToManeuver.isFinite &&
        distanceToManeuver <= kDriverNavR1NearManeuverCameraDistanceM;
    final progress = _lastNavRouteProgress;
    final confidence = _lastNavConfidence;
    final activeNav = _isActiveDriverNavEngineContext();
    final hasReliableSnap = activeNav && confidence != null
        ? confidence.trustRouteSnap
        : (progress?.hasReliableSnap ?? _useMatchedVisual);
    return NavCameraPolicyInput(
      timestamp: DateTime.now(),
      liveRideActive: _liveRideActive,
      cameraFollowMode: _cameraMode == _CameraMode.follow,
      manualRecenter: manualRecenter,
      speedKmh: _speedKmhFor(pos),
      accuracyM: pos.accuracy.isFinite && pos.accuracy > 0
          ? pos.accuracy
          : null,
      routeConfidence: progress?.confidence,
      offRouteLikely: progress?.offRouteLikely ?? _offRouteLikely,
      // NAV-R12-H: adaptation signals widen the zoom context.
      routeDeviationLikely: progress?.routeDeviationLikely ?? false,
      oppositeDirectionLikely: progress?.oppositeDirectionLikely ?? false,
      backwardProgressLikely: progress?.backwardProgressLikely ?? false,
      reroutePending: _isRerouting,
      distanceToManeuverM: distanceToManeuver,
      nearManeuver: nearManeuver,
      waitingMode: _isWaiting,
      hasReliableSnap: hasReliableSnap,
    );
  }

  ({
    bool shouldFollow,
    double zoom,
    double tilt,
    double bearingModeWeight,
    String reason,
  })
  _resolveNavCameraPolicy(geo.Position pos, {required bool manualRecenter}) {
    final input = _buildNavCameraPolicyInput(
      pos,
      manualRecenter: manualRecenter,
    );
    try {
      final output = _driverNavCameraPolicy.update(input);
      _lastNavCameraPolicy = output;
      var shouldFollow = output.shouldFollow;
      var zoom = output.zoom;
      var tilt = output.tilt;
      var bearingModeWeight = output.bearingModeWeight;
      var reason = output.reason;
      final confidence = _lastNavConfidence;
      if (confidence != null && _isActiveDriverNavEngineContext()) {
        if (!confidence.allowCameraAggression && !manualRecenter) {
          // NAV-R12-H: lower clamp follows the wider dynamic zoom range.
          zoom = (zoom - 0.35).clamp(
            DriverNavCameraPolicy.minZoom,
            DriverNavCameraPolicy.maxZoom,
          );
          tilt = (tilt - 2.0).clamp(44.0, 66.0);
          bearingModeWeight =
              (bearingModeWeight * (confidence.trustBearing ? 0.65 : 0.35))
                  .clamp(0.1, 1.0);
          reason = '${reason}_r6_cautious';
        }
        if (confidence.cameraScore < 45.0 && !manualRecenter) {
          shouldFollow = false;
          reason = 'r6_low_camera_confidence';
        }
      }
      _logNavBounded(
        'NAV_R5_CAMERA_POLICY',
        'zoom=${zoom.toStringAsFixed(1)} '
            'targetZoom=${output.targetZoom.toStringAsFixed(1)} '
            'zoomReason=${output.zoomReason} '
            'tilt=${tilt.toStringAsFixed(1)} '
            'follow=$shouldFollow reason=$reason',
        intervalMs: 2000,
      );
      unawaited(
        NavDiagnosticsRecorder.instance.recordNavEngineEvent(
          tag: 'NAV_R5_CAMERA_POLICY',
          fields: <String, dynamic>{
            'zoom': zoom,
            'targetZoom': output.targetZoom,
            'zoomReason': output.zoomReason,
            'tilt': tilt,
            'follow': shouldFollow,
            'reason': reason,
          },
        ),
      );
      return (
        shouldFollow: shouldFollow,
        zoom: zoom,
        tilt: tilt,
        bearingModeWeight: bearingModeWeight,
        reason: reason,
      );
    } catch (_) {
      final fallback = _followCameraZoomPitchFor(pos);
      return (
        shouldFollow: true,
        zoom: fallback.zoom,
        tilt: fallback.pitch,
        bearingModeWeight: 1.0,
        reason: fallback.reason,
      );
    }
  }

  int _navRouteProgressRouteFingerprintFor() {
    if (_routeCoords.length < 2) return 0;
    final first = _routeCoords.first;
    final last = _routeCoords.last;
    return Object.hash(
      _routeCoords.length,
      first.lat,
      first.lon,
      last.lat,
      last.lon,
    );
  }

  void _ensureNavRouteProgressRouteFresh() {
    final fingerprint = _navRouteProgressRouteFingerprintFor();
    if (fingerprint != _navRouteProgressRouteFingerprint) {
      _navRouteProgressRouteFingerprint = fingerprint;
      _driverNavRouteProgress.reset();
      _lastNavRouteProgress = null;
      _resetNavCameraPolicyState();
      _resetNavConfidenceState();
      _resetNavMotionPredictionState();
      _resetNavInstructionPolicyState();
    }
  }

  List<NavRoutePoint> _navRoutePointsFromCoords() {
    return _routeCoords
        .map((p) => NavRoutePoint(latitude: p.lat, longitude: p.lon))
        .toList(growable: false);
  }

  NavRouteProgressOutput? _updateNavRouteProgressForPosition(geo.Position pos) {
    if (!_isActiveDriverNavEngineContext()) {
      return null;
    }
    if (_routeCoords.length < 2) {
      return null;
    }

    _ensureNavRouteProgressRouteFresh();
    try {
      final output = _driverNavRouteProgress.update(
        NavRouteProgressInput(
          timestamp: pos.timestamp,
          rawLatitude: pos.latitude,
          rawLongitude: pos.longitude,
          rawHeading: pos.heading.isFinite && pos.heading >= 0
              ? pos.heading
              : null,
          speedKmh: _speedKmhFor(pos),
          accuracyM: pos.accuracy.isFinite && pos.accuracy > 0
              ? pos.accuracy
              : null,
          routePoints: _navRoutePointsFromCoords(),
        ),
      );
      _lastNavRouteProgress = output;
      _logNavBounded(
        'NAV_R4_PROGRESS',
        'segment=${output.segmentIndex ?? -1} '
            'confidence=${output.confidence.round()} '
            'snapDistM=${output.snapDistanceM.toStringAsFixed(1)} '
            'forward=${output.forwardProgress} '
            'offRoute=${output.offRouteLikely} '
            'reason=${output.reason}',
        intervalMs: 1500,
      );
      unawaited(
        NavDiagnosticsRecorder.instance.recordNavEngineEvent(
          tag: 'NAV_R4_PROGRESS',
          fields: <String, dynamic>{
            'segment': output.segmentIndex ?? -1,
            'confidence': output.confidence.round(),
            'snapDistM': output.snapDistanceM,
            'forward': output.forwardProgress,
            'offRoute': output.offRouteLikely,
            'reason': output.reason,
          },
        ),
      );
      return output;
    } catch (_) {
      _lastNavRouteProgress = null;
      return null;
    }
  }

  _RouteSnap? _routeSnapFromProgressOrFallback(_LonLat rawPoint) {
    final progress = _lastNavRouteProgress;
    if (_isActiveDriverNavEngineContext() &&
        progress != null &&
        progress.snappedLatitude != null &&
        progress.snappedLongitude != null &&
        progress.segmentIndex != null) {
      return DriverRouteSnap(
        point: _LonLat(progress.snappedLongitude!, progress.snappedLatitude!),
        distanceFromRouteM: progress.snapDistanceM,
        distanceAlongRouteM: progress.distanceAlongRouteM ?? 0.0,
        segmentIndex: progress.segmentIndex!,
        segmentT: 0.0,
      );
    }
    return _snapToRoute(rawPoint);
  }

  /// NAV-OS-R2: forward-looking route bearing from progress. Walks the
  /// polyline ahead of the snapped point, so it can never return a
  /// previous/backward segment bearing.
  double? _routeBearingFromProgress(NavRouteProgressOutput? progress) {
    if (progress == null ||
        progress.segmentIndex == null ||
        _routeCoords.length < 2) {
      return null;
    }
    final i = progress.segmentIndex!.clamp(0, _routeCoords.length - 2);
    final speedKmh = _lastPos != null ? _speedKmhFor(_lastPos!) : 0.0;
    final lookaheadM = (speedKmh / 3.6 * 1.2).clamp(8.0, 30.0);
    return driverForwardRouteBearing(
      _routeCoords,
      segmentIndex: i,
      snappedLat: progress.snappedLatitude ?? _routeCoords[i].lat,
      snappedLon: progress.snappedLongitude ?? _routeCoords[i].lon,
      lookaheadM: lookaheadM,
    );
  }

  /// NAV-OS-R2: forward route bearing with an anti-reverse guard. If the
  /// candidate bearing is ~180° off the movement/GPS direction (snap landed on
  /// an anti-parallel segment), it looks further ahead along the route; if
  /// that still disagrees, returns null so callers fall back to GPS heading.
  double? _resolveForwardRouteBearing(geo.Position pos, {_RouteSnap? snap}) {
    final progress = _lastNavRouteProgress;

    double? bearingAt(double lookaheadM) {
      if (_routeCoords.length < 2) return null;
      if (progress != null && progress.segmentIndex != null) {
        final i = progress.segmentIndex!.clamp(0, _routeCoords.length - 2);
        return driverForwardRouteBearing(
          _routeCoords,
          segmentIndex: i,
          snappedLat: progress.snappedLatitude ?? _routeCoords[i].lat,
          snappedLon: progress.snappedLongitude ?? _routeCoords[i].lon,
          lookaheadM: lookaheadM,
        );
      }
      if (snap != null) {
        return driverForwardRouteBearing(
          _routeCoords,
          segmentIndex: snap.segmentIndex,
          snappedLat: snap.point.lat,
          snappedLon: snap.point.lon,
          lookaheadM: lookaheadM,
        );
      }
      return null;
    }

    final speedKmh = _speedKmhFor(pos);
    final baseLookaheadM = (speedKmh / 3.6 * 1.2).clamp(8.0, 30.0);
    var bearing = bearingAt(baseLookaheadM);
    var reversedGuard = false;
    final gpsHeading = pos.heading.isFinite && pos.heading >= 0
        ? pos.heading
        : null;
    final reference = speedKmh >= 6.0
        ? (_lastMovementBearing ?? gpsHeading)
        : null;
    double? delta;
    if (bearing != null && reference != null) {
      delta = NavBearingSmoother.bearingDelta(reference, bearing);
      if (delta.abs() > 150.0) {
        reversedGuard = true;
        // Prefer the next forward segment further along the route.
        final ahead = bearingAt(baseLookaheadM + 35.0);
        final aheadDelta = ahead == null
            ? null
            : NavBearingSmoother.bearingDelta(reference, ahead);
        if (ahead != null && aheadDelta != null && aheadDelta.abs() <= 150.0) {
          bearing = ahead;
          delta = aheadDelta;
        } else {
          bearing = null;
        }
      }
    }
    _lastR2ReversedGuard = reversedGuard;
    _lastR2BearingDeltaDeg = delta;
    return bearing;
  }

  static String _r2BearingSourceLabel(String source) {
    if (source == 'route' || source.startsWith('route_segment')) {
      return 'forward_route';
    }
    if (source == 'gps' || source == 'gps_heading' || source == 'movement') {
      return 'gps';
    }
    if (source == 'last' || source.startsWith('last_stable')) return 'hold';
    return 'fallback';
  }

  static String _navR11SourceFromEngine(String engineSource) {
    if (engineSource.startsWith('route_segment')) return 'route';
    if (engineSource == 'gps_heading' || engineSource == 'movement') {
      return 'gps';
    }
    if (engineSource.startsWith('last_stable')) return 'last';
    return 'fallback';
  }

  bool _routeProgressMatchedVisual(NavRouteProgressOutput? progress) {
    return progress != null &&
        progress.hasReliableSnap &&
        progress.forwardProgress &&
        !progress.offRouteLikely;
  }

  void _updateRouteSnapState(geo.Position pos) {
    final rawPoint = _LonLat(pos.longitude, pos.latitude);
    final progress = _updateNavRouteProgressForPosition(pos);
    _updateNavConfidenceForPosition(pos);
    final snap = _routeSnapFromProgressOrFallback(rawPoint);
    _lastRouteSnap = snap;
    final bool canUseMatched =
        _isActiveDriverNavEngineContext() && progress != null
        ? _routeProgressMatchedVisual(progress) &&
              (_lastNavConfidence?.trustRouteSnap ?? true)
        : _canSnapToRoute(pos, snap);
    if (canUseMatched) {
      _matchEnterHits += 1;
      _matchExitHits = 0;
      if (!_useMatchedVisual && _matchEnterHits >= 2) {
        _useMatchedVisual = true;
      }
    } else {
      _matchExitHits += 1;
      _matchEnterHits = 0;
      if (_useMatchedVisual && _matchExitHits >= 2) {
        _useMatchedVisual = false;
      }
    }
    if (_useMatchedVisual && snap != null) {
      _lastVisualProgressM = snap.distanceAlongRouteM;
    }

    final offRouteThreshold = math.max(70.0, _snapThresholdFor(pos) + 25.0);
    final snapDistance = snap?.distanceFromRouteM ?? double.infinity;
    if (_isActiveDriverNavEngineContext() && progress != null) {
      if (progress.offRouteLikely) {
        _offRouteHitCount += 1;
      } else if (progress.hasReliableSnap) {
        _offRouteHitCount = 0;
      } else if (snapDistance > offRouteThreshold) {
        _offRouteHitCount += 1;
      } else {
        _offRouteHitCount = 0;
      }
    } else if (snapDistance > offRouteThreshold) {
      _offRouteHitCount += 1;
    } else {
      _offRouteHitCount = 0;
    }
    // NAV-R12-B: route deviation (opposite direction / backward progress)
    // confirms off-route much faster than the plain snap-distance path.
    final oppositeDirection = progress?.oppositeDirectionLikely ?? false;
    final strongOppositeDirection =
        progress?.routeDeviationReason == 'opposite_heading_strong';
    final backwardProgress = progress?.backwardProgressLikely ?? false;
    final routeDeviation = progress?.routeDeviationLikely ?? false;
    final int offRouteHitsRequired;
    if (strongOppositeDirection) {
      offRouteHitsRequired = 1;
    } else if (routeDeviation) {
      offRouteHitsRequired = 2;
    } else if (progress?.offRouteLikely == true || snapDistance > 55.0) {
      offRouteHitsRequired = 2;
    } else {
      offRouteHitsRequired = 3;
    }
    final offRoute = _offRouteHitCount >= offRouteHitsRequired;
    if (offRoute) {
      _offRouteReason = oppositeDirection
          ? (strongOppositeDirection
                ? 'opposite_direction_strong'
                : 'opposite_direction')
          : (backwardProgress ? 'backward_progress' : 'snap_distance');
    } else {
      _offRouteReason = 'none';
    }
    if (offRoute != _offRouteLikely) {
      _offRouteLikely = offRoute;
      if (!offRoute) {
        _offRouteRerouteDebounceStartedAt = null;
      }
      // NAV-R12-B: rebuild immediately so the route-adaptation banner state
      // shows on the same fix, not only once a route fetch starts.
      if (mounted) setState(() {});
    }
    _logNavR12RouteDeviation(
      pos: pos,
      progress: progress,
      snapDistance: snapDistance,
      routeDeviation: routeDeviation,
      oppositeDirection: oppositeDirection,
      backwardProgress: backwardProgress,
    );

    final displayPoint = (_useMatchedVisual && snap != null)
        ? snap.point
        : rawPoint;
    _lastMarkerLagM = geo.Geolocator.distanceBetween(
      rawPoint.lat,
      rawPoint.lon,
      displayPoint.lat,
      displayPoint.lon,
    );

    _logNavBounded(
      'NAV_MATCH',
      'rawLat=${rawPoint.lat.toStringAsFixed(6)} rawLon=${rawPoint.lon.toStringAsFixed(6)} '
          'snapDistM=${snapDistance.isFinite ? snapDistance.toStringAsFixed(1) : 'inf'} '
          'gpsAccuracyM=${(pos.accuracy.isFinite ? pos.accuracy : -1).toStringAsFixed(1)} '
          'useMatchedVisual=$_useMatchedVisual reason=${canUseMatched ? 'confidence_ok' : 'confidence_low'}',
    );
  }

  /// NAV-R12-B: bounded, PII-safe route-deviation diagnostics (no lat/lng).
  void _logNavR12RouteDeviation({
    required geo.Position pos,
    required NavRouteProgressOutput? progress,
    required double snapDistance,
    required bool routeDeviation,
    required bool oppositeDirection,
    required bool backwardProgress,
  }) {
    final rerouteEligible = _canAttemptOffRouteReroute();
    final signature =
        '$_offRouteReason|$routeDeviation|$oppositeDirection|'
        '$backwardProgress|$_offRouteLikely|$rerouteEligible';
    final changed = signature != _lastNavR12OffRouteSignature;
    _lastNavR12OffRouteSignature = signature;
    final headingDelta = progress?.headingDeltaDeg;
    _logNavBounded(
      'NAV_R12_ROUTE_DEVIATION',
      'reason=$_offRouteReason '
          'speedKmh=${_speedKmhFor(pos).toStringAsFixed(1)} '
          'snapDistM=${snapDistance.isFinite ? snapDistance.toStringAsFixed(1) : 'inf'} '
          'headingDeltaDeg=${headingDelta?.toStringAsFixed(0) ?? 'na'} '
          'routeDeviationLikely=$routeDeviation '
          'oppositeDirectionLikely=$oppositeDirection '
          'backwardProgressLikely=$backwardProgress '
          'offRouteLikely=$_offRouteLikely '
          'rerouteEligible=$rerouteEligible',
      intervalMs: changed ? 1 : 2000,
    );
    if (changed) {
      unawaited(
        NavDiagnosticsRecorder.instance.recordNavEngineEvent(
          tag: 'NAV_R12_ROUTE_DEVIATION',
          fields: <String, dynamic>{
            'reason': _offRouteReason,
            'speedKmh': _speedKmhFor(pos).round(),
            'snapDistM': snapDistance.isFinite ? snapDistance.round() : -1,
            'headingDeltaDeg': headingDelta?.round() ?? -1,
            'routeDeviationLikely': routeDeviation,
            'oppositeDirectionLikely': oppositeDirection,
            'backwardProgressLikely': backwardProgress,
            'offRouteLikely': _offRouteLikely,
            'rerouteEligible': rerouteEligible,
          },
        ),
      );
    }
  }

  bool _isRouteDeviationOffRouteReason() {
    return _offRouteReason == 'opposite_direction' ||
        _offRouteReason == 'opposite_direction_strong' ||
        _offRouteReason == 'backward_progress';
  }

  Duration _rerouteCooldownFor() {
    // NAV-R12-B: a failed reroute retries on a short backoff; route-deviation
    // off-route corrects on a short cooldown. Camera follow mode no longer
    // gates detection/eligibility — it only affects camera behavior.
    if (_lastRerouteFailed) return _rerouteFailedRetryBackoff;
    if (_isRouteDeviationOffRouteReason()) {
      return _rerouteCooldownRouteDeviation;
    }
    return _rerouteCooldown;
  }

  bool _canAttemptOffRouteReroute() {
    if (!_liveRideActive || _isWaiting) return false;
    if (_lastPos == null || _isRerouting) return false;
    if (_routeCoords.length < 2) return false;
    if (!_offRouteLikely) return false;

    final lastReroute = _lastRerouteAt;
    if (lastReroute != null &&
        DateTime.now().difference(lastReroute) < _rerouteCooldownFor()) {
      return false;
    }

    if (_routePhase == _RideRoutePhase.toPickup) {
      return _activeBooking != null && _activeTripId == null;
    }
    if (_routePhase == _RideRoutePhase.trip) {
      final booking = _activeBooking;
      if (booking != null && _activeTripId != null) return true;
      if (_directRideActive &&
          (_directRideDestinationText ?? '').trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Duration _offRouteRerouteDebounceFor() {
    // NAV-R12-B: confirmed route deviation must start the reroute on the
    // next fix, not seconds later.
    if (_offRouteReason == 'opposite_direction_strong') {
      return const Duration(milliseconds: 500);
    }
    if (_isRouteDeviationOffRouteReason()) {
      return const Duration(milliseconds: 800);
    }
    final progress = _lastNavRouteProgress;
    if (progress != null && progress.offRouteLikely) {
      final snapDist = progress.snapDistanceM;
      final conf = progress.confidence;
      if (snapDist > 55.0 && conf < 45.0) {
        return const Duration(milliseconds: 1200);
      }
      if (snapDist > 45.0 || conf < 55.0) {
        return const Duration(milliseconds: 1800);
      }
    }
    return const Duration(milliseconds: 2500);
  }

  void _evaluateOffRouteReroute() {
    if (!_offRouteLikely) {
      _offRouteRerouteDebounceStartedAt = null;
      return;
    }
    if (!_canAttemptOffRouteReroute()) return;

    final debounceStart = _offRouteRerouteDebounceStartedAt;
    if (debounceStart == null) {
      _offRouteRerouteDebounceStartedAt = DateTime.now();
      return;
    }
    if (DateTime.now().difference(debounceStart) <
        _offRouteRerouteDebounceFor()) {
      return;
    }

    unawaited(
      _triggerOffRouteReroute(
        reason: _isRouteDeviationOffRouteReason()
            ? _offRouteReason
            : 'off_route',
      ),
    );
  }

  void _resetOffRouteStateAfterReroute() {
    _offRouteHitCount = 0;
    _offRouteLikely = false;
    _offRouteReason = 'none';
    _offRouteRerouteDebounceStartedAt = null;
    _matchEnterHits = 0;
    _matchExitHits = 0;
    _useMatchedVisual = false;
    _lastVisualProgressM = null;
    _lastRouteSnap = null;
    _routeLineProgressTrimmed = false;
    _lastRouteLineTrimProgressM = 0.0;
    _lastRouteLineTrimAt = null;
  }

  String _reroutePhaseLabel() {
    return _routePhase == _RideRoutePhase.toPickup ? 'toPickup' : 'toDropoff';
  }

  Future<void> _triggerOffRouteReroute({required String reason}) async {
    if (_isRerouting || !_canAttemptOffRouteReroute()) return;

    _isRerouting = true;
    _rerouteReason = reason;
    _lastRerouteAt = DateTime.now();
    _offRouteRerouteDebounceStartedAt = null;
    final phaseLabel = _reroutePhaseLabel();
    final rerouteStartedAt = DateTime.now();
    debugPrint('[NAV_REROUTE] phase=$phaseLabel reason=$reason start=1');
    unawaited(
      NavDiagnosticsRecorder.instance.recordRerouteEvent(
        offRoute: _offRouteLikely,
        triggerReason: reason,
        phase: phaseLabel,
      ),
    );
    if (kDebugMode) {
      debugPrint('[NAV_REROUTE] ui=loading reason=rerouting');
    }
    if (mounted) setState(() {});

    var ok = false;
    try {
      if (_routePhase == _RideRoutePhase.toPickup) {
        final booking = _activeBooking;
        if (booking != null) {
          await _buildNavRouteToPickup(booking);
          ok = _routeCoords.length >= 2;
        }
      } else {
        final booking = _activeBooking;
        if (booking != null && _activeTripId != null) {
          await _buildNavRouteToDestination(booking);
          ok = _routeCoords.length >= 2;
        } else if (_directRideActive) {
          final destination = (_directRideDestinationText ?? '').trim();
          if (destination.isNotEmpty) {
            await _buildDirectRouteToDestination(destination);
            ok = _routeCoords.length >= 2;
          }
        }
      }
    } catch (_) {
      ok = false;
    } finally {
      if (ok) {
        _resetOffRouteStateAfterReroute();
      }
      // NAV-R12-B: failed reroutes retry on a short backoff instead of the
      // full cooldown (see _rerouteCooldownFor).
      _lastRerouteFailed = !ok;
      _isRerouting = false;
      _rerouteReason = null;
      debugPrint(
        '[NAV_REROUTE] phase=$phaseLabel reason=$reason result=${ok ? 'ok' : 'fail'}',
      );
      unawaited(
        NavDiagnosticsRecorder.instance.recordRerouteEvent(
          offRoute: _offRouteLikely,
          triggerReason: reason,
          durationMs: DateTime.now()
              .difference(rerouteStartedAt)
              .inMilliseconds,
          success: ok,
          phase: phaseLabel,
        ),
      );
      if (!ok) {
        _toast(
          _tr(
            nl: 'Route bijwerken mislukt. Probeer Google Maps of Waze.',
            en: 'Could not update route. Try Google Maps or Waze.',
            fr: 'Mise a jour de l\'itineraire impossible. Essayez Google Maps ou Waze.',
            es: 'No se pudo actualizar la ruta. Prueba Google Maps o Waze.',
          ),
        );
      }
      if (mounted) setState(() {});
    }
  }

  _LonLat _displayRoutePointFor(geo.Position pos) {
    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    if (_useMatchedVisual && snap != null) return snap.point;
    return _LonLat(pos.longitude, pos.latitude);
  }

  ({_LonLat point, String source, double? snapDistM}) _driverMarkerDisplayFor(
    geo.Position pos,
  ) {
    final raw = _LonLat(pos.longitude, pos.latitude);
    final snap = _lastRouteSnap ?? _snapToRoute(raw);
    final activeNav =
        _cameraMode == _CameraMode.follow &&
        _liveRideActive &&
        _routeCoords.length >= 2;

    if (activeNav) {
      final progress = _lastNavRouteProgress;
      final confidence = _lastNavConfidence;
      if (_routeProgressMatchedVisual(progress) &&
          (confidence?.trustRouteSnap ?? true) &&
          progress!.snappedLatitude != null &&
          progress.snappedLongitude != null) {
        return (
          point: _LonLat(progress.snappedLongitude!, progress.snappedLatitude!),
          source: 'route_snap',
          snapDistM: progress.snapDistanceM,
        );
      }
      if (progress?.offRouteLikely == true) {
        return (
          point: raw,
          source: 'raw',
          snapDistM: progress?.snapDistanceM ?? snap?.distanceFromRouteM,
        );
      }
    }

    if (!activeNav) {
      if (_useMatchedVisual && snap != null) {
        return (
          point: snap.point,
          source: 'route_snap',
          snapDistM: snap.distanceFromRouteM,
        );
      }
      return (
        point: raw,
        source: 'fallback',
        snapDistM: snap?.distanceFromRouteM,
      );
    }

    if (snap == null) {
      return (point: raw, source: 'raw', snapDistM: null);
    }

    if (_offRouteLikely) {
      return (point: raw, source: 'raw', snapDistM: snap.distanceFromRouteM);
    }

    final markerSnapThresholdM = math.max(45.0, _snapThresholdFor(pos));
    if (snap.distanceFromRouteM <= markerSnapThresholdM) {
      return (
        point: snap.point,
        source: 'route_snap',
        snapDistM: snap.distanceFromRouteM,
      );
    }

    return (point: raw, source: 'raw', snapDistM: snap.distanceFromRouteM);
  }

  double? _effectiveRouteProgressM(geo.Position pos) {
    final progress = _lastNavRouteProgress;
    if (_isActiveDriverNavEngineContext() &&
        _routeProgressMatchedVisual(progress) &&
        progress?.distanceAlongRouteM != null) {
      return progress!.distanceAlongRouteM;
    }
    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    if (_useMatchedVisual && snap != null) return snap.distanceAlongRouteM;
    return null;
  }

  List<_LonLat> _routeCoordsFromSnap(_RouteSnap snap) {
    return driverRouteCoordsFromSnap(_routeCoords, snap);
  }

  Future<void> _syncVisibleRouteLineWithProgress(
    geo.Position pos, {
    String reason = 'progress_update',
  }) async {
    if (_routeCoords.length < 2 || _routeLineManager == null) return;
    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    final progressM = _effectiveRouteProgressM(pos);

    if (_cameraMode != _CameraMode.follow || !_liveRideActive) {
      if (_routeLineProgressTrimmed) {
        _routeLineProgressTrimmed = false;
        _lastRouteLineTrimProgressM = 0.0;
        await _drawRouteLine(_routeCoords, force: true);
        _logNavBounded(
          'NAV_OS_R2_ROUTE_PROGRESS_LINE',
          'completedM=0 remainingM=${driverRouteLengthMeters(_routeCoords).toStringAsFixed(0)} reason=reset_full',
        );
      }
      return;
    }

    if (!_useMatchedVisual || snap == null || progressM == null) {
      if (_routeLineProgressTrimmed) {
        _routeLineProgressTrimmed = false;
        _lastRouteLineTrimProgressM = 0.0;
        await _drawRouteLine(_routeCoords, force: true);
        _logNavBounded(
          'NAV_OS_R2_ROUTE_PROGRESS_LINE',
          'completedM=0 remainingM=${driverRouteLengthMeters(_routeCoords).toStringAsFixed(0)} reason=reset_no_snap',
        );
      }
      _logNavBounded(
        'NAV_PROGRESS',
        'progressM=-1 routeLineTrimmed=false markerLagM=${_lastMarkerLagM.toStringAsFixed(1)}',
      );
      return;
    }

    // NAV-OS-R2: throttle split-line redraws (>=12m progress or >=320ms).
    final now = DateTime.now();
    final deltaM = (progressM - _lastRouteLineTrimProgressM).abs();
    final recentDraw =
        _lastRouteLineTrimAt != null &&
        now.difference(_lastRouteLineTrimAt!).inMilliseconds < 320;
    if (_routeLineProgressTrimmed && deltaM < 12.0 && recentDraw) {
      _logNavBounded(
        'NAV_PROGRESS',
        'progressM=${progressM.toStringAsFixed(1)} routeLineTrimmed=true markerLagM=${_lastMarkerLagM.toStringAsFixed(1)}',
      );
      return;
    }

    // NAV-OS-R2: split geometry — muted grey behind the taxi, blue ahead.
    final remaining = _routeCoordsFromSnap(snap);
    final completed = driverRouteCoordsUpToSnap(_routeCoords, snap);
    if (remaining.length >= 2) {
      _routeLineProgressTrimmed = true;
      _lastRouteLineTrimProgressM = progressM;
      _lastRouteLineTrimAt = now;
      await _drawRouteLine(remaining, force: true, completedCoords: completed);
      final totalM = driverRouteLengthMeters(_routeCoords);
      final remainingM = (totalM - progressM).clamp(0.0, totalM);
      _logNavBounded(
        'NAV_OS_R2_ROUTE_PROGRESS_LINE',
        'completedM=${progressM.toStringAsFixed(0)} '
            'remainingM=${remainingM.toStringAsFixed(0)} reason=$reason',
      );
    }
    _logNavBounded(
      'NAV_PROGRESS',
      'progressM=${progressM.toStringAsFixed(1)} routeLineTrimmed=${remaining.length >= 2} markerLagM=${_lastMarkerLagM.toStringAsFixed(1)}',
    );
  }

  double? _routeBearingAtSnap(_RouteSnap? snap) {
    return driverRouteBearingAtSnap(_routeCoords, snap);
  }

  bool _isActiveDriverNavEngineContext() {
    return _cameraMode == _CameraMode.follow &&
        _liveRideActive &&
        _routeCoords.length >= 2;
  }

  NavEngineInput _buildNavEngineInput(geo.Position pos, _RouteSnap? snap) {
    final markerDisplay = _driverMarkerDisplayFor(pos);
    final progress = _lastNavRouteProgress;
    final confidence = _lastNavConfidence;
    final activeNav = _isActiveDriverNavEngineContext();
    final progressReliable = activeNav && progress != null
        ? progress.hasReliableSnap
        : markerDisplay.source == 'route_snap';
    final hasReliableSnap =
        progressReliable &&
        (!activeNav || confidence == null || confidence.trustRouteSnap);
    final snappedLat = hasReliableSnap
        ? (progress?.snappedLatitude ?? snap?.point.lat)
        : null;
    final snappedLon = hasReliableSnap
        ? (progress?.snappedLongitude ?? snap?.point.lon)
        : null;
    final routeBearing = _resolveForwardRouteBearing(pos, snap: snap);
    return NavEngineInput(
      timestamp: DateTime.now(),
      rawLatitude: pos.latitude,
      rawLongitude: pos.longitude,
      snappedLatitude: snappedLat,
      snappedLongitude: snappedLon,
      hasReliableSnap: hasReliableSnap,
      rawHeading: pos.heading.isFinite && pos.heading >= 0 ? pos.heading : null,
      routeBearing: routeBearing,
      speedKmh: _speedKmhFor(pos),
      accuracyM: pos.accuracy.isFinite && pos.accuracy > 0
          ? pos.accuracy
          : null,
      cameraFollowMode: _cameraMode == _CameraMode.follow,
      liveRideActive: _liveRideActive,
      movementBearing: _lastMovementBearing,
      offRouteLikely: progress?.offRouteLikely ?? _offRouteLikely,
      trustBearing: confidence?.trustBearing ?? true,
      routeConfidence: progress?.confidence ?? confidence?.routeScore,
      routeDeviationLikely: progress?.routeDeviationLikely ?? false,
      oppositeDirectionLikely: progress?.oppositeDirectionLikely ?? false,
      backwardProgressLikely: progress?.backwardProgressLikely ?? false,
      headingDeltaDeg: progress?.headingDeltaDeg,
      forwardProgress: progress?.forwardProgress ?? true,
    );
  }

  String _navEngineRefreshKeyFor(geo.Position pos) {
    return '${pos.timestamp.millisecondsSinceEpoch}|'
        '${pos.latitude.toStringAsFixed(6)}|'
        '${pos.longitude.toStringAsFixed(6)}';
  }

  void _refreshNavEngineForPosition(geo.Position pos) {
    final key = _navEngineRefreshKeyFor(pos);
    if (_lastNavEngineRefreshKey == key) return;
    _lastNavEngineRefreshKey = key;

    if (!_isActiveDriverNavEngineContext()) {
      _driverNavEngine.reset();
      _lastNavEngineOutput = null;
      _resetNavR3MotionState();
      _resetNavMotionPredictionState();
      _lastNavConfidence = null;
      return;
    }

    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    final priorOutput = _lastNavEngineOutput;
    final fromVisual = _navR3CaptureVisual(priorOutput);
    try {
      final output = _driverNavEngine.update(_buildNavEngineInput(pos, snap));
      _lastNavEngineOutput = output;
      _applyNavEngineMotionTarget(
        output,
        fromVisual: fromVisual,
        priorOutput: priorOutput,
      );
      final progress = _lastNavRouteProgress;
      _driverNavMotionPrediction.noteEngineUpdate(
        timestamp: output.timestamp,
        displayLatitude: output.displayLatitude,
        displayLongitude: output.displayLongitude,
        bearing: output.bearing,
        trustRouteSnap:
            _lastNavConfidence?.trustRouteSnap ??
            progress?.hasReliableSnap ??
            false,
      );
      _lastNavMotionPrediction = null;
      _startNavMotionTimerIfNeeded();
      _logNavBounded(
        'NAV_ENGINE_OUT',
        'source=${output.markerSource} animate=${output.shouldAnimateMarker} '
            'bearing=${output.bearing.toStringAsFixed(1)} '
            'bearingSource=${_driverNavEngine.lastBearingSource} '
            'speedKmh=${output.speedKmh?.toStringAsFixed(1) ?? 'na'} '
            'accuracyM=${output.accuracyM?.toStringAsFixed(1) ?? 'na'} '
            'cameraReason=${output.cameraReason}',
        intervalMs: 2000,
      );
      _logNavBounded(
        'NAV_OS_R2_BEARING',
        'source=${_r2BearingSourceLabel(_driverNavEngine.lastBearingSource)} '
            'delta=${_lastR2BearingDeltaDeg?.toStringAsFixed(1) ?? 'na'} '
            'reversedGuard=$_lastR2ReversedGuard',
        intervalMs: 2000,
      );
      _logNavR11Bearing(
        source: _navR11SourceFromEngine(_driverNavEngine.lastBearingSource),
        speedKmh: output.speedKmh ?? 0.0,
        accuracyM: output.accuracyM,
        confidence:
            _lastNavRouteProgress?.confidence ?? _lastNavConfidence?.routeScore,
        deltaDeg: priorOutput != null
            ? NavBearingSmoother.bearingDelta(
                priorOutput.bearing,
                output.bearing,
              )
            : null,
        appliedDeg: output.bearing,
        reason: _driverNavEngine.lastBearingReason,
        headingDeltaDeg: _lastNavRouteProgress?.headingDeltaDeg,
        routeDeviationLikely:
            _lastNavRouteProgress?.routeDeviationLikely ?? false,
        oppositeDirectionLikely:
            _lastNavRouteProgress?.oppositeDirectionLikely ?? false,
        backwardProgressLikely:
            _lastNavRouteProgress?.backwardProgressLikely ?? false,
        offRouteLikely:
            _lastNavRouteProgress?.offRouteLikely ?? _offRouteLikely,
        routeBearingAllowed: _driverNavEngine.lastRouteBearingAllowed,
      );
      unawaited(
        NavDiagnosticsRecorder.instance.recordNavEngineEvent(
          tag: 'NAV_ENGINE_OUT',
          fields: <String, dynamic>{
            'source': output.markerSource,
            'animate': output.shouldAnimateMarker,
            'bearing': output.bearing.round(),
            'bearingSource': _driverNavEngine.lastBearingSource,
            'speedKmh': output.speedKmh?.round(),
            'accuracyM': output.accuracyM?.round(),
            'cameraReason': output.cameraReason,
          },
        ),
      );
    } catch (_) {
      _driverNavEngine.reset();
      _lastNavEngineOutput = null;
      _resetNavR3MotionState();
    }
  }

  void _logNavR3Motion({
    required String state,
    required int durationMs,
    required double progress,
    required bool animate,
  }) {
    _logNavBounded(
      'NAV_R3_MOTION',
      'state=$state durationMs=$durationMs '
          'progress=${progress.toStringAsFixed(2)} animate=$animate',
      intervalMs: state == 'tick' ? 1200 : 1,
    );
  }

  void _stopNavR3MotionTimer() {
    _navR3MotionTimer?.cancel();
    _navR3MotionTimer = null;
  }

  void _resetNavR3MotionState() {
    _stopNavR3MotionTimer();
    if (_navR3MotionActive || _navR3VisualLat != null) {
      _logNavR3Motion(
        state: 'reset',
        durationMs: 0,
        progress: 0.0,
        animate: false,
      );
    }
    _navR3MotionActive = false;
    _navR3VisualLat = null;
    _navR3VisualLon = null;
    _navR3VisualBearing = 0.0;
    _navR3AnimStartedAt = null;
    _navR3AnimDuration = const Duration(milliseconds: 1000);
    _lastNavMotionPrediction = null;
  }

  bool _isWeakGpsForPrediction(geo.Position? pos) {
    if (pos == null) return true;
    if (!_isGpsQualityAcceptableForCamera(pos)) return true;
    final accuracy = pos.accuracy;
    return accuracy.isFinite && accuracy > 28.0;
  }

  NavMotionPredictionInput _buildNavMotionPredictionInput() {
    final output = _lastNavEngineOutput!;
    final confidence = _lastNavConfidence;
    final progress = _lastNavRouteProgress;
    final pos = _lastPos;
    final trustRouteSnap = confidence?.trustRouteSnap ?? false;
    final trustBearing = confidence?.trustBearing ?? false;
    return NavMotionPredictionInput(
      timestamp: DateTime.now(),
      lastDisplayLatitude: _navR3VisualLat ?? output.displayLatitude,
      lastDisplayLongitude: _navR3VisualLon ?? output.displayLongitude,
      lastReliableLatitude: trustRouteSnap
          ? (progress?.snappedLatitude ?? output.displayLatitude)
          : null,
      lastReliableLongitude: trustRouteSnap
          ? (progress?.snappedLongitude ?? output.displayLongitude)
          : null,
      bearing: _navR3VisualBearing,
      speedKmh: output.speedKmh ?? (pos != null ? _speedKmhFor(pos) : null),
      routeBearing:
          _routeBearingFromProgress(progress) ??
          _routeBearingAtSnap(_lastRouteSnap),
      trustRouteSnap: trustRouteSnap,
      trustBearing: trustBearing,
      offRouteLikely: progress?.offRouteLikely ?? _offRouteLikely,
      gpsAccuracyM:
          output.accuracyM ??
          (pos != null && pos.accuracy.isFinite && pos.accuracy > 0
              ? pos.accuracy
              : null),
      liveRideActive: _liveRideActive,
      gapSinceLastEngineMs: _gapSinceLastNavEngineMs(),
      weakGps: _isWeakGpsForPrediction(pos),
    );
  }

  NavMotionPredictionOutput? _updateNavMotionPrediction() {
    if (!_isActiveDriverNavEngineContext() || _lastNavEngineOutput == null) {
      _lastNavMotionPrediction = null;
      return null;
    }
    try {
      final result = _driverNavMotionPrediction.update(
        _buildNavMotionPredictionInput(),
      );
      _lastNavMotionPrediction = result;
      _logNavBounded(
        'NAV_R7_PREDICTION',
        'active=${result.predictionActive} '
            'durationMs=${_gapSinceLastNavEngineMs()} '
            'confidence=${result.confidence.round()} '
            'reason=${result.reason}',
        intervalMs: 1200,
      );
      unawaited(
        NavDiagnosticsRecorder.instance.recordNavEngineEvent(
          tag: 'NAV_R7_PREDICTION',
          fields: <String, dynamic>{
            'active': result.predictionActive,
            'durationMs': _gapSinceLastNavEngineMs(),
            'confidence': result.confidence.round(),
            'reason': result.reason,
          },
        ),
      );
      return result;
    } catch (_) {
      _lastNavMotionPrediction = null;
      return null;
    }
  }

  void _startNavMotionTimerIfNeeded() {
    if (!_isActiveDriverNavEngineContext()) return;
    if (_navR3MotionTimer != null) return;
    _navR3MotionTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _navR3MotionTick();
    });
  }

  ({double lat, double lon, double bearing})? _navR3CaptureVisual(
    NavEngineOutput? priorOutput,
  ) {
    if (_navR3VisualLat != null && _navR3VisualLon != null) {
      return (
        lat: _navR3VisualLat!,
        lon: _navR3VisualLon!,
        bearing: _navR3VisualBearing,
      );
    }
    if (priorOutput != null) {
      return (
        lat: priorOutput.displayLatitude,
        lon: priorOutput.displayLongitude,
        bearing: priorOutput.bearing,
      );
    }
    return null;
  }

  Duration _navR3DurationFor(
    NavEngineOutput output,
    NavEngineOutput? priorOutput,
  ) {
    var intervalMs = 800;
    if (priorOutput != null) {
      intervalMs = output.timestamp
          .difference(priorOutput.timestamp)
          .inMilliseconds;
    }
    intervalMs = intervalMs.clamp(280, 3200);
    final intervalT = (intervalMs - 280) / 2920.0;
    var durationMs = (360 + intervalT * 420).round();
    final speed = output.speedKmh ?? 0.0;
    if (speed > 50) {
      durationMs -= 180;
    } else if (speed > 35) {
      durationMs -= 130;
    } else if (speed > 20) {
      durationMs -= 70;
    }
    if (speed < 8) durationMs += 90;
    return Duration(milliseconds: durationMs.clamp(320, 820));
  }

  static double _shortestBearingDelta(double from, double to) {
    var delta = (to - from) % 360.0;
    if (delta > 180.0) delta -= 360.0;
    if (delta < -180.0) delta += 360.0;
    return delta;
  }

  static double _lerpBearingShortest(double from, double to, double t) {
    final delta = _shortestBearingDelta(from, to);
    var bearing = from + delta * t;
    bearing %= 360.0;
    if (bearing < 0) bearing += 360.0;
    return bearing;
  }

  void _applyNavEngineMotionTarget(
    NavEngineOutput output, {
    required ({double lat, double lon, double bearing})? fromVisual,
    required NavEngineOutput? priorOutput,
  }) {
    if (!_isActiveDriverNavEngineContext()) {
      _resetNavR3MotionState();
      return;
    }

    final toLat = output.displayLatitude;
    final toLon = output.displayLongitude;
    final speed = output.speedKmh ?? 0.0;
    final fromLat = fromVisual?.lat ?? toLat;
    final fromLon = fromVisual?.lon ?? toLon;
    final fromBearing = fromVisual?.bearing ?? output.bearing;
    final toBearing = speed < 3.0 ? fromBearing : output.bearing;

    if (output.shouldAnimateMarker && priorOutput != null) {
      final intervalMs = output.timestamp
          .difference(priorOutput.timestamp)
          .inMilliseconds;
      if (intervalMs < 480 && speed > 28) {
        _navR3VisualLat = toLat;
        _navR3VisualLon = toLon;
        _navR3VisualBearing = toBearing;
        _navR3MotionActive = false;
        _navR3AnimStartedAt = null;
        _stopNavR3MotionTimer();
        _logNavR3Motion(
          state: 'fast_snap',
          durationMs: 0,
          progress: 1.0,
          animate: false,
        );
        _startNavMotionTimerIfNeeded();
        return;
      }
    }

    if (!output.shouldAnimateMarker) {
      _navR3VisualLat = toLat;
      _navR3VisualLon = toLon;
      _navR3VisualBearing = toBearing;
      _navR3MotionActive = false;
      _navR3AnimStartedAt = null;
      _stopNavR3MotionTimer();
      _logNavR3Motion(
        state: 'jump',
        durationMs: 0,
        progress: 1.0,
        animate: false,
      );
      _startNavMotionTimerIfNeeded();
      return;
    }

    _navR3FromLat = fromLat;
    _navR3FromLon = fromLon;
    _navR3ToLat = toLat;
    _navR3ToLon = toLon;
    _navR3FromBearing = fromBearing;
    _navR3ToBearing = toBearing;
    _navR3VisualLat = fromLat;
    _navR3VisualLon = fromLon;
    _navR3VisualBearing = fromBearing;
    _navR3AnimStartedAt = DateTime.now();
    _navR3AnimDuration = _navR3DurationFor(output, priorOutput);
    _navR3MotionActive = true;
    _logNavR3Motion(
      state: 'start',
      durationMs: _navR3AnimDuration.inMilliseconds,
      progress: 0.0,
      animate: true,
    );
    _startNavMotionTimerIfNeeded();
  }

  void _startNavR3MotionTimer() {
    _startNavMotionTimerIfNeeded();
  }

  double _navR3MotionProgress() {
    final startedAt = _navR3AnimStartedAt;
    if (!_navR3MotionActive || startedAt == null) return 1.0;
    final durationMs = _navR3AnimDuration.inMilliseconds;
    if (durationMs <= 0) return 1.0;
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    return (elapsedMs / durationMs).clamp(0.0, 1.0);
  }

  ({double lat, double lon, double bearing}) _navR3InterpolatedVisual(
    NavEngineOutput output,
  ) {
    if (!_navR3MotionActive) {
      if (_navR3VisualLat != null && _navR3VisualLon != null) {
        return (
          lat: _navR3VisualLat!,
          lon: _navR3VisualLon!,
          bearing: _navR3VisualBearing,
        );
      }
      return (
        lat: output.displayLatitude,
        lon: output.displayLongitude,
        bearing: output.bearing,
      );
    }

    final progress = _navR3MotionProgress();
    final t = progress;
    final lat = _navR3FromLat + (_navR3ToLat - _navR3FromLat) * t;
    final lon = _navR3FromLon + (_navR3ToLon - _navR3FromLon) * t;
    final speed = output.speedKmh ?? 0.0;
    final bearing = speed < 3.0
        ? _navR3FromBearing
        : _lerpBearingShortest(_navR3FromBearing, _navR3ToBearing, t);
    return (lat: lat, lon: lon, bearing: bearing);
  }

  void _navR3MotionTick() {
    if (!mounted) {
      _resetNavR3MotionState();
      _resetNavMotionPredictionState();
      return;
    }
    if (!_isActiveDriverNavEngineContext() ||
        _map == null ||
        _mapStyleChanging ||
        _driverPointManager == null ||
        _driverMarker == null) {
      _resetNavR3MotionState();
      _resetNavMotionPredictionState();
      return;
    }

    final output = _lastNavEngineOutput;
    if (output == null) {
      _resetNavR3MotionState();
      _resetNavMotionPredictionState();
      return;
    }

    if (_navR3MotionActive) {
      final progress = _navR3MotionProgress();
      final visual = _navR3InterpolatedVisual(output);
      _navR3VisualLat = visual.lat;
      _navR3VisualLon = visual.lon;
      _navR3VisualBearing = visual.bearing;
      _logNavR3Motion(
        state: 'tick',
        durationMs: _navR3AnimDuration.inMilliseconds,
        progress: progress,
        animate: true,
      );
      unawaited(
        _applyDriverMarkerVisualOnly(visual.lat, visual.lon, visual.bearing),
      );
      if (progress < 1.0) return;

      _navR3VisualLat = _navR3ToLat;
      _navR3VisualLon = _navR3ToLon;
      _navR3VisualBearing = _navR3ToBearing;
      _navR3MotionActive = false;
      _navR3AnimStartedAt = null;
    }

    final prediction = _updateNavMotionPrediction();
    if (prediction?.predictionActive == true) {
      _navR3VisualLat = prediction!.predictedLatitude;
      _navR3VisualLon = prediction.predictedLongitude;
      _navR3VisualBearing = prediction.predictedBearing;
      unawaited(
        _applyDriverMarkerVisualOnly(
          prediction.predictedLatitude,
          prediction.predictedLongitude,
          prediction.predictedBearing,
        ),
      );
      return;
    }

    _lastNavMotionPrediction = null;
    final gapMs = _gapSinceLastNavEngineMs();
    final weakGps = _isWeakGpsForPrediction(_lastPos);
    if (gapMs < 450 && !weakGps) {
      _stopNavR3MotionTimer();
    }
  }

  Future<void> _applyDriverMarkerVisualOnly(
    double lat,
    double lon,
    double bearing,
  ) async {
    if (!_canUpdateDriverMarker) return;
    final mgr = _driverPointManager;
    final marker = _driverMarker;
    if (mgr == null || marker == null) return;
    final p = _mbPoint(lon, lat);
    marker.geometry = p;
    marker.iconRotate = bearing;
    try {
      await mgr.update(marker);
    } catch (e) {
      if (_isMapboxAnnotationManagerLost(e)) {
        _resetDriverMarkerOnNativeError('visual_only_update');
      }
    }
  }

  ({_LonLat point, double bearing}) _resolveNavVisualForLiveNav(
    geo.Position pos,
    _RouteSnap? snap, {
    bool allowPrediction = true,
  }) {
    final output = _lastNavEngineOutput;
    if (output != null && _isActiveDriverNavEngineContext()) {
      if (_navR3MotionActive) {
        final visual = _navR3InterpolatedVisual(output);
        _navR3VisualLat = visual.lat;
        _navR3VisualLon = visual.lon;
        _navR3VisualBearing = visual.bearing;
        return (
          point: _LonLat(visual.lon, visual.lat),
          bearing: visual.bearing,
        );
      }
      final prediction = _lastNavMotionPrediction;
      if (allowPrediction &&
          prediction != null &&
          prediction.predictionActive) {
        _navR3VisualLat = prediction.predictedLatitude;
        _navR3VisualLon = prediction.predictedLongitude;
        _navR3VisualBearing = prediction.predictedBearing;
        return (
          point: _LonLat(
            prediction.predictedLongitude,
            prediction.predictedLatitude,
          ),
          bearing: prediction.predictedBearing,
        );
      }
      final visual = _navR3InterpolatedVisual(output);
      _navR3VisualLat = visual.lat;
      _navR3VisualLon = visual.lon;
      _navR3VisualBearing = visual.bearing;
      return (point: _LonLat(visual.lon, visual.lat), bearing: visual.bearing);
    }
    final markerDisplay = _driverMarkerDisplayFor(pos);
    return (point: markerDisplay.point, bearing: _markerBearingFor(pos, snap));
  }

  ({_LonLat point, double bearing}) _resolveNavVisualForMarker(
    geo.Position pos,
    _RouteSnap? snap,
  ) {
    return _resolveNavVisualForLiveNav(pos, snap);
  }

  Future<bool> _ensureDriverTaxiMarkerBytes() async {
    if (_driverTaxiMarkerLoadAttempted) return _driverTaxiMarkerAvailable;
    _driverTaxiMarkerLoadAttempted = true;
    try {
      final data = await rootBundle.load(kDriverTaxiMarkerAssetPath);
      _driverTaxiMarkerBytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      _driverTaxiMarkerAvailable = _driverTaxiMarkerBytes!.isNotEmpty;
      if (_driverTaxiMarkerAvailable) {
        debugPrint('[NAV_MARKER] taxi_asset=loaded');
      }
    } catch (_) {
      _driverTaxiMarkerAvailable = false;
      _driverTaxiMarkerBytes = null;
      debugPrint('[NAV_MARKER] taxi_asset=missing');
    }
    return _driverTaxiMarkerAvailable;
  }

  double _markerBearingFor(geo.Position pos, _RouteSnap? snap) {
    final speedKmh = _speedKmhFor(pos);
    final meta = _adaptiveBearingFor(pos, snap: snap);
    final confidence = _lastNavConfidence;
    var bearingWeight = 1.0;
    if (confidence != null) {
      bearingWeight = confidence.trustBearing ? 0.9 : 0.45;
      if (_lastNavRouteProgress?.offRouteLikely ?? _offRouteLikely) {
        bearingWeight *= 0.35;
      } else if (confidence.routeScore < 55.0) {
        bearingWeight *= 0.65;
      }
    }
    return _smoothFollowCameraBearing(
      meta.bearing,
      speedKmh,
      bearingModeWeight: bearingWeight,
    );
  }

  Future<mb.PointAnnotation?> _createDriverMarkerAnnotation({
    required mb.PointAnnotationManager mgr,
    required mb.Point geometry,
    required double markerBearing,
  }) async {
    final taxiReady = await _ensureDriverTaxiMarkerBytes();
    final taxiBytes = _driverTaxiMarkerBytes;
    if (taxiReady && taxiBytes != null) {
      try {
        final marker = await mgr.create(
          mb.PointAnnotationOptions(
            geometry: geometry,
            image: taxiBytes,
            iconAnchor: mb.IconAnchor.CENTER,
            iconSize: _driverTaxiIconSizeForCurrentZoom(),
            iconRotate: markerBearing,
          ),
        );
        _driverMarkerUsesTaxiAsset = true;
        _driverMarkerIcon = 'fluxidi-driver-taxi';
        debugPrint('[NAV_MARKER] mode=taxi');
        return marker;
      } catch (_) {
        debugPrint('[NAV_MARKER] mode=taxi_fallback_triangle');
      }
    }

    _driverMarkerUsesTaxiAsset = false;
    try {
      _driverMarkerIcon = 'triangle-15';
      return await mgr.create(
        mb.PointAnnotationOptions(
          geometry: geometry,
          iconImage: _driverMarkerIcon,
          iconColor: 0xFFFFD21F,
          iconSize: driverFallbackMarkerIconSizeForZoom(_lastMapCameraZoom),
          iconRotate: markerBearing,
        ),
      );
    } catch (_) {
      _driverMarkerIcon = 'marker-15';
      return await mgr.create(
        mb.PointAnnotationOptions(
          geometry: geometry,
          iconImage: _driverMarkerIcon,
          iconColor: 0xFFFFD21F,
          iconSize: driverFallbackMarkerIconSizeForZoom(_lastMapCameraZoom),
          iconRotate: markerBearing,
        ),
      );
    }
  }

  /// Returns true when the native marker create/update was applied.
  Future<bool> _updateDriverMarker(
    geo.Position pos, {
    bool moveCamera = false,
  }) async {
    if (!_canUpdateDriverMarker) {
      _logNavR12Marker(event: 'skipped_not_ready');
      return false;
    }
    final mgr = _driverPointManager;
    if (mgr == null) return false;

    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    _refreshNavEngineForPosition(pos);
    final visual = _resolveNavVisualForMarker(pos, snap);
    if (_lastNavEngineOutput == null) {
      final markerDisplay = _driverMarkerDisplayFor(pos);
      _logNavBounded(
        'NAV_MARKER',
        'source=${markerDisplay.source} snapDistM=${markerDisplay.snapDistM?.round() ?? -1}',
      );
    }
    final p = _mbPoint(visual.point.lon, visual.point.lat);
    final markerBearing = visual.bearing;
    // Fresh GPS-driven visual supersedes any pre-style-swap snapshot.
    _taxiVisualSnapshotForStyleSwap = null;
    final taxiReady = await _ensureDriverTaxiMarkerBytes();
    if (!_canUpdateDriverMarker || _driverPointManager != mgr) return false;
    final wantsTaxi = taxiReady && _driverTaxiMarkerBytes != null;

    if (_driverMarker != null && _driverMarkerUsesTaxiAsset != wantsTaxi) {
      try {
        await mgr.delete(_driverMarker!);
      } catch (e) {
        if (_isMapboxAnnotationManagerLost(e)) {
          _resetDriverMarkerOnNativeError('delete_for_asset_swap');
          return false;
        }
      }
      _driverMarker = null;
    }

    if (_driverMarker == null) {
      try {
        await mgr.deleteAll();
      } catch (e) {
        if (_isMapboxAnnotationManagerLost(e)) {
          _resetDriverMarkerOnNativeError('delete_all_before_create');
          return false;
        }
      }
      try {
        _driverMarker = await _createDriverMarkerAnnotation(
          mgr: mgr,
          geometry: p,
          markerBearing: markerBearing,
        );
      } catch (e) {
        _noteMarkerUpdateFailure('create_marker', e);
        return false;
      }
    } else {
      try {
        _driverMarker!.geometry = p;
        _driverMarker!.iconRotate = markerBearing;
        await mgr.update(_driverMarker!);
      } catch (e) {
        _noteMarkerUpdateFailure('update_marker', e);
        return false;
      }
    }
    _consecutiveMarkerUpdateFailures = 0;
    // NAV-R12-D: icon-size/puck sync are non-critical extra native round
    // trips — throttle them off the per-fix hot path.
    final auxNow = DateTime.now();
    if (_lastMarkerAuxSyncAt == null ||
        auxNow.difference(_lastMarkerAuxSyncAt!).inMilliseconds >= 1500) {
      _lastMarkerAuxSyncAt = auxNow;
      await _syncDriverMarkerIconSizeForZoom();
      await _syncMapboxUserLocationPuckVisibility();
    }

    final markerDisplay = _driverMarkerDisplayFor(pos);
    final markerNow = DateTime.now();
    final markerLagMs = _lastNavDiagMarkerAt == null
        ? null
        : markerNow.difference(_lastNavDiagMarkerAt!).inMilliseconds;
    _lastNavDiagMarkerAt = markerNow;
    final String bearingSource;
    final double? bearingDeltaDeg;
    if (_isActiveDriverNavEngineContext() && _lastNavEngineOutput != null) {
      bearingSource = _driverNavEngine.lastBearingSource;
      bearingDeltaDeg = pos.heading.isFinite && pos.heading >= 0
          ? NavBearingSmoother.bearingDelta(pos.heading, markerBearing)
          : null;
    } else {
      final meta = _adaptiveBearingFor(pos, snap: snap);
      bearingSource = meta.source;
      bearingDeltaDeg = meta.bearingDeltaDeg;
    }
    unawaited(
      NavDiagnosticsRecorder.instance.recordMarkerUpdate(
        source: markerDisplay.source,
        snapDistM: markerDisplay.snapDistM,
        bearing: markerBearing,
        markerLagMs: markerLagMs,
        bearingSource: bearingSource,
        bearingDeltaDeg: bearingDeltaDeg,
      ),
    );
    _logNavR12Marker(
      event: 'applied',
      markerSource: markerDisplay.source,
      markerLagMs: markerLagMs,
    );

    if (moveCamera && _cameraMode != _CameraMode.follow) {
      await _map?.flyTo(
        mb.CameraOptions(center: p, zoom: 13.5),
        mb.MapAnimationOptions(duration: 700),
      );
    }
    return true;
  }

  /// NAV-R12-D: marker create/update exception handling — a lost manager
  /// resets immediately; other native errors degrade after two consecutive
  /// failures (stale/detached annotation) so self-heal can recreate.
  void _noteMarkerUpdateFailure(String reason, Object e) {
    _logNavR12Marker(event: 'failed_$reason');
    if (_isMapboxAnnotationManagerLost(e)) {
      _resetDriverMarkerOnNativeError(reason);
      return;
    }
    _consecutiveMarkerUpdateFailures += 1;
    if (_consecutiveMarkerUpdateFailures >= 2) {
      _consecutiveMarkerUpdateFailures = 0;
      _resetDriverMarkerOnNativeError('${reason}_repeated');
    }
  }

  void _recordNavDiagCameraUpdate({
    required bool follow,
    String? skippedReason,
    double? zoom,
    double? tilt,
    double? bearing,
  }) {
    if (!NavDiagnosticsRecorder.instance.hasActiveSession) return;
    unawaited(
      NavDiagnosticsRecorder.instance.recordCameraUpdate(
        follow: follow,
        skippedReason: skippedReason,
        zoom: zoom,
        tilt: tilt,
        bearing: bearing,
      ),
    );
  }

  /// NAV-R12-E1: bounded, PII-safe camera decision diagnostics (no lat/lng).
  void _logNavR12Camera({
    required String animation,
    String? targetSource,
    String? skipReason,
    int? targetAgeMs,
  }) {
    final progress = _lastNavRouteProgress;
    final cameraPolicy = _lastNavCameraPolicy;
    final maneuverDistanceM =
        _navInstructionSnapshot?.distanceToManeuverMeters ?? _nextNavDistanceM;
    final signature =
        '$animation|${targetSource ?? ''}|${skipReason ?? ''}|'
        '${cameraPolicy?.zoomReason ?? ''}|'
        '${progress?.routeDeviationLikely ?? false}|'
        '${progress?.offRouteLikely ?? _offRouteLikely}';
    final changed = signature != _lastNavR12CameraSignature;
    _lastNavR12CameraSignature = signature;
    _logNavBounded(
      'NAV_R12_CAMERA',
      'cameraAnimation=$animation '
          'cameraTargetSource=${targetSource ?? 'na'} '
          'cameraSkippedReason=${skipReason ?? 'none'} '
          'zoom=${cameraPolicy?.zoom.toStringAsFixed(1) ?? 'na'} '
          'targetZoom=${cameraPolicy?.targetZoom.toStringAsFixed(1) ?? 'na'} '
          'zoomReason=${cameraPolicy?.zoomReason ?? 'na'} '
          'tilt=${cameraPolicy?.tilt.toStringAsFixed(1) ?? 'na'} '
          'speedKmh=${_lastPos != null ? _speedKmhFor(_lastPos!).toStringAsFixed(1) : 'na'} '
          'maneuverDistanceM=${maneuverDistanceM?.round() ?? -1} '
          'routeDeviationLikely=${progress?.routeDeviationLikely ?? false} '
          'oppositeDirectionLikely=${progress?.oppositeDirectionLikely ?? false} '
          'backwardProgressLikely=${progress?.backwardProgressLikely ?? false} '
          'offRouteLikely=${progress?.offRouteLikely ?? _offRouteLikely} '
          'reroutePending=$_isRerouting '
          'predictionActive=${_lastNavMotionPrediction?.predictionActive ?? false} '
          'targetAgeMs=${targetAgeMs ?? -1} '
          'followMode=${_cameraMode == _CameraMode.follow} '
          'animationInFlight=$_followCameraInFlight '
          'pendingCameraUpdate=${_pendingFollowCameraPos != null}',
      intervalMs: changed ? 1 : 2000,
    );
  }

  /// NAV-R12-E1: remember the newest camera target (last-wins) instead of
  /// dropping the fix when the camera is throttled or animating.
  void _queuePendingFollowCamera(
    geo.Position pos, {
    required String skipReason,
    int? retryDelayMs,
  }) {
    _pendingFollowCameraPos = pos;
    _logNavR12Camera(animation: 'queued_latest', skipReason: skipReason);
    if (retryDelayMs != null) {
      _armPendingFollowCameraTimer(retryDelayMs);
    }
  }

  void _armPendingFollowCameraTimer(int delayMs) {
    if (_pendingFollowCameraTimer?.isActive ?? false) return;
    _pendingFollowCameraTimer = Timer(
      Duration(milliseconds: delayMs.clamp(16, 1000)),
      () {
        _pendingFollowCameraTimer = null;
        _runPendingFollowCamera();
      },
    );
  }

  void _runPendingFollowCamera() {
    final pos = _pendingFollowCameraPos;
    _pendingFollowCameraPos = null;
    if (pos == null || !mounted) return;
    // Manual pan/zoom wins: no forced recenter outside follow mode.
    if (_cameraMode != _CameraMode.follow) return;
    if (_map == null || _mapStyleChanging || _posSub == null) return;
    _logNavR12Camera(animation: 'applied_pending');
    unawaited(_followCameraTesla(pos, cameraReason: 'pending_latest'));
  }

  void _resetPendingFollowCamera() {
    _pendingFollowCameraTimer?.cancel();
    _pendingFollowCameraTimer = null;
    _pendingFollowCameraPos = null;
  }

  Future<void> _followCameraTesla(
    geo.Position pos, {
    bool force = false,
    String cameraReason = 'normal_follow',
  }) async {
    if (_mapStyleChanging) {
      _navValidationPendingCameraSkipReason = 'style_changing';
      _recordNavDiagCameraUpdate(
        follow: false,
        skippedReason: 'style_changing',
      );
      return;
    }
    _navValidationPendingCameraFollowed = false;
    _navValidationPendingCameraSkipReason = null;

    final manualRecenter = force || cameraReason == 'manual_recenter';
    final policy = _resolveNavCameraPolicy(pos, manualRecenter: manualRecenter);
    if (!policy.shouldFollow && !manualRecenter) {
      _navValidationPendingCameraSkipReason = policy.reason;
      _logNavBounded(
        'NAV_R5_CAMERA_POLICY',
        'zoom=${policy.zoom.toStringAsFixed(1)} '
            'tilt=${policy.tilt.toStringAsFixed(1)} '
            'follow=false reason=${policy.reason}',
        intervalMs: 2000,
      );
      _recordNavDiagCameraUpdate(
        follow: false,
        skippedReason: policy.reason,
        zoom: policy.zoom,
        tilt: policy.tilt,
      );
      return;
    }

    if (!force && !_isGpsQualityAcceptableForCamera(pos)) {
      _gpsQualityWeak = true;
      _navValidationPendingCameraSkipReason = 'gps_weak';
      final ageSec = _gpsFixAgeSec(pos);
      final acc = pos.accuracy.isFinite ? pos.accuracy : -1.0;
      _logNavBounded(
        'NAV_GPS',
        'cameraSkip=1 ageSec=${ageSec?.toStringAsFixed(1) ?? 'na'} accuracyM=${acc.toStringAsFixed(1)}',
      );
      _recordNavDiagCameraUpdate(
        follow: false,
        skippedReason: 'gps_weak',
        zoom: policy.zoom,
        tilt: policy.tilt,
      );
      return;
    }
    _gpsQualityWeak = false;

    final now = DateTime.now();
    final last = _lastFollowCameraAt;
    final throttleMs = _followCameraThrottleMsFor(pos);
    if (!force &&
        last != null &&
        now.difference(last).inMilliseconds < throttleMs) {
      _navValidationPendingCameraSkipReason = 'throttled';
      _recordNavDiagCameraUpdate(
        follow: false,
        skippedReason: 'throttled',
        zoom: policy.zoom,
        tilt: policy.tilt,
      );
      // NAV-R12-E1: last-wins — retry with the newest target once the
      // throttle window has passed instead of dropping this fix.
      final elapsedMs = now.difference(last).inMilliseconds;
      _queuePendingFollowCamera(
        pos,
        skipReason: 'throttled',
        retryDelayMs: throttleMs - elapsedMs + 8,
      );
      return;
    }
    if (!force && _followCameraInFlight) {
      _navValidationPendingCameraSkipReason = 'in_flight';
      _recordNavDiagCameraUpdate(
        follow: false,
        skippedReason: 'in_flight',
        zoom: policy.zoom,
        tilt: policy.tilt,
      );
      // NAV-R12-E1: the running animation's completion applies this target.
      _queuePendingFollowCamera(pos, skipReason: 'in_flight');
      return;
    }
    _lastFollowCameraAt = now;
    _followCameraInFlight = true;
    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    final speedKmh = _speedKmhFor(pos);

    // NAV-R12-E1: pure target decision — deviation prefers the freshest
    // raw/live position, prediction only when confident and fresh.
    final progress = _lastNavRouteProgress;
    final targetDecision = NavCameraTargetPolicy.resolve(
      NavCameraTargetInput(
        followMode: _cameraMode == _CameraMode.follow,
        manualRecenter: manualRecenter,
        routeDeviationLikely: progress?.routeDeviationLikely ?? false,
        oppositeDirectionLikely: progress?.oppositeDirectionLikely ?? false,
        backwardProgressLikely: progress?.backwardProgressLikely ?? false,
        offRouteLikely: progress?.offRouteLikely ?? _offRouteLikely,
        hasReliableSnap: progress?.hasReliableSnap ?? false,
        predictionActive: _lastNavMotionPrediction?.predictionActive ?? false,
        predictionAgeMs: _gapSinceLastNavEngineMs(),
        cameraScore: _lastNavConfidence?.cameraScore ?? 0.0,
      ),
    );
    if (targetDecision.source == NavCameraTargetSource.skipped) {
      _followCameraInFlight = false;
      _navValidationPendingCameraSkipReason = targetDecision.reason;
      _logNavR12Camera(
        animation: 'skipped_manual',
        targetSource: targetDecision.sourceLabel,
        skipReason: targetDecision.reason,
      );
      _recordNavDiagCameraUpdate(
        follow: false,
        skippedReason: targetDecision.reason,
        zoom: policy.zoom,
        tilt: policy.tilt,
      );
      return;
    }
    var visual =
        _isActiveDriverNavEngineContext() && _lastNavEngineOutput != null
        ? _resolveNavVisualForLiveNav(
            pos,
            snap,
            allowPrediction:
                targetDecision.source == NavCameraTargetSource.prediction,
          )
        : (
            point: _displayRoutePointFor(pos),
            bearing: _adaptiveBearingFor(pos, snap: snap).bearing,
          );
    if (targetDecision.forceRawTarget) {
      // Route is adapting: aim at the live driver position, keep the
      // already-resolved display bearing (NAV-R12-C output).
      visual = (
        point: _LonLat(pos.longitude, pos.latitude),
        bearing: visual.bearing,
      );
    }
    final heading = _smoothFollowCameraBearing(
      visual.bearing,
      speedKmh,
      bearingModeWeight: policy.bearingModeWeight,
    );
    final p = _mbPoint(visual.point.lon, visual.point.lat);
    final resolvedReason = manualRecenter ? 'manual_recenter' : policy.reason;
    _lastMapCameraZoom = policy.zoom;
    unawaited(_syncDriverMarkerIconSizeForZoom());
    _logNavBounded(
      'NAV_R1_CAMERA',
      'zoom=${policy.zoom.toStringAsFixed(1)} reason=$resolvedReason',
      intervalMs: 2500,
    );
    final animMs = force ? 220 : _followCameraAnimMsFor(pos);
    final fixAgeSec = _gpsFixAgeSec(pos);
    _logNavR12Camera(
      animation: 'started',
      targetSource: targetDecision.sourceLabel,
      targetAgeMs: fixAgeSec != null ? (fixAgeSec * 1000).round() : null,
    );

    try {
      await _map?.flyTo(
        mb.CameraOptions(
          center: p,
          zoom: policy.zoom,
          bearing: heading,
          pitch: policy.tilt,
          padding: mb.MbxEdgeInsets(
            top:
                MediaQuery.of(context).padding.top +
                (MediaQuery.of(context).orientation == Orientation.landscape
                    ? 56
                    : 175),
            left: 24,
            bottom:
                MediaQuery.of(context).padding.bottom +
                (MediaQuery.of(context).orientation == Orientation.landscape
                    ? 96
                    : 240),
            right: 24,
          ),
        ),
        mb.MapAnimationOptions(duration: animMs),
      );
      _navValidationPendingCameraFollowed = true;
      _navValidationPendingCameraSkipReason = null;
      _recordNavDiagCameraUpdate(
        follow: true,
        zoom: policy.zoom,
        tilt: policy.tilt,
        bearing: heading,
      );
    } finally {
      _followCameraInFlight = false;
      // NAV-R12-E1: apply the newest queued target now that the animation
      // is done (throttle inside _followCameraTesla still applies).
      if (_pendingFollowCameraPos != null) {
        _armPendingFollowCameraTimer(16);
      }
    }
  }

  /// NAV-R12-E2: true while the banner may not confidently show an
  /// old-route maneuver (deviation signals from NAV-R12-B or reroute in
  /// flight). Mirrors NavInstructionPolicyInput.routeAdaptationActive.
  bool _navRouteAdaptationActive() {
    final progress = _lastNavRouteProgress;
    return _isRerouting ||
        (progress?.offRouteLikely ?? _offRouteLikely) ||
        (progress?.routeDeviationLikely ?? false) ||
        (progress?.oppositeDirectionLikely ?? false) ||
        (progress?.backwardProgressLikely ?? false);
  }

  /// NAV-R12-E2: bounded, PII-safe banner decision diagnostics (no lat/lng).
  void _logNavR12Banner({required String state, required String reason}) {
    final progress = _lastNavRouteProgress;
    final signature = '$state|$reason|$_routeStepsVersion|$_nextStepIndex';
    final changed = signature != _lastNavR12BannerSignature;
    _lastNavR12BannerSignature = signature;
    _logNavBounded(
      'NAV_R12_BANNER',
      'bannerState=$state '
          'reason=$reason '
          'instructionIndex=$_nextStepIndex '
          'routeDeviationLikely=${progress?.routeDeviationLikely ?? false} '
          'oppositeDirectionLikely=${progress?.oppositeDirectionLikely ?? false} '
          'backwardProgressLikely=${progress?.backwardProgressLikely ?? false} '
          'offRouteLikely=${progress?.offRouteLikely ?? _offRouteLikely} '
          'reroutePending=$_isRerouting '
          'routeReliable=${progress?.hasReliableSnap ?? _useMatchedVisual} '
          'maneuverType=${(_nextNavType ?? '').isEmpty ? 'na' : _nextNavType} '
          'routeVersion=$_routeStepsVersion',
      intervalMs: changed ? 1 : 2000,
    );
  }

  void _updateNextNavInstruction(geo.Position pos) {
    final nextInstruction = computeDriverNextNavInstruction(
      routeSteps: _routeSteps,
      nextStepIndex: _nextStepIndex,
      posLat: pos.latitude,
      posLon: pos.longitude,
      lastRouteSnap: _lastRouteSnap,
      routeCoords: _routeCoords,
      useMatchedVisual: _useMatchedVisual,
    );
    _nextStepIndex = nextInstruction.nextStepIndex;
    if (nextInstruction.reResolved) {
      _logNavR12Banner(state: 're_resolved', reason: 'backtrack_re_resolve');
    } else if (_navRouteAdaptationActive()) {
      _logNavR12Banner(
        state: nextInstruction.hasInstruction
            ? 'suppressed_stale'
            : 'route_adaptation',
        reason: _isRerouting ? 'reroute_pending' : 'route_deviation_signals',
      );
    } else {
      _logNavR12Banner(
        state: nextInstruction.shouldClear ? 'skipped' : 'route_instruction',
        reason: nextInstruction.progressSource,
      );
    }
    final snapshot = buildDriverNavInstructionSnapshot(
      routeSteps: _routeSteps,
      nextStepIndex: _nextStepIndex,
      posLat: pos.latitude,
      posLon: pos.longitude,
      lastRouteSnap: _lastRouteSnap,
      routeCoords: _routeCoords,
      useMatchedVisual: _useMatchedVisual,
      tr: _tr,
      navStepsLoading: _navStepsLoading,
    );
    _navInstructionSnapshot = snapshot;

    if (nextInstruction.shouldClear) {
      if (_nextNavInstruction != null ||
          _nextNavStreet != null ||
          _nextNavDistanceM != null ||
          _nextNavType != null ||
          _nextNavModifier != null ||
          _navInstructionSnapshot != NavInstructionSnapshot.none) {
        if (mounted) {
          setState(() {
            _nextNavInstruction = null;
            _nextNavStreet = null;
            _nextNavDistanceM = null;
            _nextNavType = null;
            _nextNavModifier = null;
            _navInstructionSnapshot = snapshot;
          });
        } else {
          _nextNavInstruction = null;
          _nextNavStreet = null;
          _nextNavDistanceM = null;
          _nextNavType = null;
          _nextNavModifier = null;
        }
      }
      return;
    }

    final distanceM = nextInstruction.distanceMeters!;
    _logNavBounded(
      'NAV_STEP',
      'progressSource=${nextInstruction.progressSource} nextDistanceM=${distanceM.toStringAsFixed(1)}',
    );
    unawaited(
      NavDiagnosticsRecorder.instance.recordManeuverProgress(
        distanceToNextM: distanceM,
        instructionType: nextInstruction.type,
        modifier: nextInstruction.modifier,
      ),
    );
    if (snapshot.hasInstruction) {
      _logNavBounded(
        'NAV_E2',
        'source=${snapshot.source.name} highway=${snapshot.isHighwayLike} lanes=${snapshot.lanes.length}',
      );
      if (_nextStepIndex >= 0 && _nextStepIndex < _routeSteps.length) {
        final step = _routeSteps[_nextStepIndex];
        final banner = step.banner;
        final rawPrimary = (banner?.primaryText ?? '').trim();
        final rawSecondaryLen = (banner?.secondaryText ?? '').trim().length;
        final displaySnap = applyDriverNavInstructionDisplayLines(
          snapshot: snapshot,
          step: step,
        );
        final swapped =
            rawPrimary.isNotEmpty &&
            displaySnap.primaryText.trim() != rawPrimary;
        final primaryKind = driverNavBannerPrimaryKind(
          primaryText: displaySnap.primaryText,
          step: step,
        );
        final tgtFrom = driverNavManeuverTargetSource(step);
        _logNavBounded(
          'NAV_E3_TEXT',
          'source=${snapshot.source.name} swapped=$swapped primaryKind=$primaryKind hasBannerSec=${rawSecondaryLen > 0 ? 1 : 0} bannerSecLen=$rawSecondaryLen tgtFrom=$tgtFrom',
        );
      }
    }

    if (!mounted) {
      _nextNavInstruction = nextInstruction.instruction;
      _nextNavStreet = nextInstruction.street;
      _nextNavDistanceM = distanceM;
      _nextNavType = nextInstruction.type;
      _nextNavModifier = nextInstruction.modifier;
      return;
    }

    setState(() {
      _nextNavInstruction = nextInstruction.instruction;
      _nextNavStreet = nextInstruction.street;
      _nextNavDistanceM = distanceM;
      _nextNavType = nextInstruction.type;
      _nextNavModifier = nextInstruction.modifier;
    });
  }

  Future<void> _buildNavRouteToPickup(BookingItem b) async {
    final epoch = _routeCleanupEpoch;
    final expectedBookingId = b.bookingId;
    if (!_isRouteTaskStillValid(
      epoch: epoch,
      expectedBookingId: expectedBookingId,
    )) {
      return;
    }
    if (_lastPos == null) return;
    final pickupText = (b.from ?? '').trim();
    final hasStoredPickup =
        _usableNavLonLat(_extractPreviewEndpoints(b).pickup) != null;
    if (pickupText.isEmpty && !hasStoredPickup) return;
    if (mounted) {
      setState(() {
        _routePhase = _RideRoutePhase.toPickup;
        _navStepsLoading = true;
      });
    } else {
      _routePhase = _RideRoutePhase.toPickup;
      _navStepsLoading = true;
    }
    debugPrint('[NAV_PHASE] toPickup');
    try {
      final fromLL = _LonLat(_lastPos!.longitude, _lastPos!.latitude);
      final toLL = await _resolvePickupLonLat(b);
      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }
      if (mounted) {
        setState(() {
          _routeCoords = coords;
          _routeKm = route.$2 / 1000.0;
          _routeDurationSec = route.$3;
        });
      } else {
        _routeCoords = coords;
        _routeKm = route.$2 / 1000.0;
        _routeDurationSec = route.$3;
      }
      if (_lastPos != null) {
        _updateRouteSnapState(_lastPos!);
        _updateNextNavInstruction(_lastPos!);
        await _syncVisibleRouteLineWithProgress(
          _lastPos!,
          reason: 'route_rebuilt',
        );
      }
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
    } catch (_) {
      // Keep previous route if pickup route fetch fails.
    } finally {
      if (_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        if (mounted) {
          setState(() => _navStepsLoading = false);
        } else {
          _navStepsLoading = false;
        }
      }
    }
  }

  Future<void> _buildNavRouteToDestination(BookingItem b) async {
    final epoch = _routeCleanupEpoch;
    final expectedBookingId = b.bookingId;
    if (!_isRouteTaskStillValid(
      epoch: epoch,
      expectedBookingId: expectedBookingId,
    )) {
      return;
    }
    if (_lastPos == null) return;
    final dropoffText = (b.to ?? '').trim();
    final hasStoredDropoff =
        _usableNavLonLat(_extractPreviewEndpoints(b).dropoff) != null;
    if (dropoffText.isEmpty && !hasStoredDropoff) return;
    if (mounted) {
      setState(() {
        _routePhase = _RideRoutePhase.trip;
        _navStepsLoading = true;
      });
    } else {
      _routePhase = _RideRoutePhase.trip;
      _navStepsLoading = true;
    }
    debugPrint('[NAV_PHASE] trip');
    try {
      final fromLL = _LonLat(_lastPos!.longitude, _lastPos!.latitude);
      final toLL = await _resolveDropoffLonLat(b);
      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }
      if (mounted) {
        setState(() {
          _routeCoords = coords;
          _routeKm = route.$2 / 1000.0;
          _routeDurationSec = route.$3;
        });
      } else {
        _routeCoords = coords;
        _routeKm = route.$2 / 1000.0;
        _routeDurationSec = route.$3;
      }
      if (_lastPos != null) {
        _updateRouteSnapState(_lastPos!);
        _updateNextNavInstruction(_lastPos!);
        await _syncVisibleRouteLineWithProgress(
          _lastPos!,
          reason: 'route_rebuilt',
        );
      }
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
    } catch (_) {
      // Keep previous route if destination route fetch fails.
    } finally {
      if (_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        if (mounted) {
          setState(() => _navStepsLoading = false);
        } else {
          _navStepsLoading = false;
        }
      }
    }
  }

  Future<void> _buildDirectRouteToDestination(String destinationText) async {
    final epoch = _routeCleanupEpoch;
    if (!_isRouteTaskStillValid(epoch: epoch, requireDirectRide: true)) {
      return;
    }
    if (_lastPos == null) return;
    final dropoffText = destinationText.trim();
    if (dropoffText.isEmpty) return;
    if (mounted) {
      setState(() {
        _routePhase = _RideRoutePhase.trip;
        _navStepsLoading = true;
      });
    } else {
      _routePhase = _RideRoutePhase.trip;
      _navStepsLoading = true;
    }
    debugPrint('[NAV_PHASE] direct_trip');
    try {
      final fromLL = _LonLat(_lastPos!.longitude, _lastPos!.latitude);
      final toLL =
          _directRideDestinationPoint ?? await _geocodeOne(dropoffText);
      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(epoch: epoch, requireDirectRide: true)) {
        return;
      }
      if (mounted) {
        setState(() {
          _routeCoords = coords;
          _routeKm = route.$2 / 1000.0;
          _routeDurationSec = route.$3;
        });
      } else {
        _routeCoords = coords;
        _routeKm = route.$2 / 1000.0;
        _routeDurationSec = route.$3;
      }
      if (_lastPos != null) {
        _updateRouteSnapState(_lastPos!);
        _updateNextNavInstruction(_lastPos!);
        await _syncVisibleRouteLineWithProgress(
          _lastPos!,
          reason: 'route_rebuilt',
        );
      }
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
      _scheduleDirectRideEstimateRefresh(reason: 'route_changed');
    } catch (e) {
      _toast('Straatrit route mislukt: $e');
    } finally {
      if (_isRouteTaskStillValid(epoch: epoch, requireDirectRide: true)) {
        if (mounted) {
          setState(() => _navStepsLoading = false);
        } else {
          _navStepsLoading = false;
        }
      }
    }
  }

  Future<void> _forceFollowCameraNow({required String caller}) async {
    geo.Position? pos = _lastPos;
    if (pos == null) {
      try {
        pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.best,
        );
        _lastPos = pos;
      } catch (_) {
        pos = null;
      }
    }

    if (pos == null) {
      _toast('GPS-locatie nog niet beschikbaar');
      return;
    }
    _updateRouteSnapState(pos);
    await _syncVisibleRouteLineWithProgress(pos);
    _refreshNavEngineForPosition(pos);
    await _followCameraTesla(pos, force: true);
  }

  double _cameraBearingFor(geo.Position pos) {
    if (pos.heading.isFinite && pos.heading >= 0) return pos.heading;
    if (_lastMovementBearing != null && _lastMovementBearing!.isFinite) {
      return _lastMovementBearing!;
    }
    if (_lastKnownBearing.isFinite && _lastKnownBearing > 0)
      return _lastKnownBearing;
    return 0.0;
  }

  bool _hasReliableRouteSnapForBearing() {
    if (!_isActiveDriverNavEngineContext()) {
      return _useMatchedVisual;
    }
    final progress = _lastNavRouteProgress;
    final confidence = _lastNavConfidence;
    return progress != null &&
        progress.hasReliableSnap &&
        progress.forwardProgress &&
        !progress.offRouteLikely &&
        (confidence?.trustRouteSnap ?? true);
  }

  void _logNavR11Bearing({
    required String source,
    required double speedKmh,
    double? accuracyM,
    double? confidence,
    double? deltaDeg,
    required double appliedDeg,
    required String reason,
    double? headingDeltaDeg,
    bool routeDeviationLikely = false,
    bool oppositeDirectionLikely = false,
    bool backwardProgressLikely = false,
    bool offRouteLikely = false,
    bool routeBearingAllowed = false,
  }) {
    if (!_isActiveDriverNavEngineContext()) return;
    _logNavBounded(
      'NAV_R11_BEARING',
      'source=$source '
          'speedKmh=${speedKmh.toStringAsFixed(1)} '
          'accuracyM=${accuracyM?.toStringAsFixed(1) ?? 'na'} '
          'confidence=${confidence?.toStringAsFixed(0) ?? 'na'} '
          'deltaDeg=${deltaDeg?.toStringAsFixed(1) ?? 'na'} '
          'headingDeltaDeg=${headingDeltaDeg?.toStringAsFixed(0) ?? 'na'} '
          'routeDeviationLikely=$routeDeviationLikely '
          'oppositeDirectionLikely=$oppositeDirectionLikely '
          'backwardProgressLikely=$backwardProgressLikely '
          'offRouteLikely=$offRouteLikely '
          'routeBearingAllowed=$routeBearingAllowed '
          'displayBearing=${appliedDeg.toStringAsFixed(1)} '
          'reason=$reason',
      intervalMs: 1200,
    );
  }

  ({
    double bearing,
    String source,
    double? gpsHeading,
    double? movementBearing,
    double? routeBearing,
    double? bearingDeltaDeg,
  })
  _adaptiveBearingFor(geo.Position pos, {_RouteSnap? snap}) {
    final speedKmh = _speedKmhFor(pos);
    final gpsHeading = (pos.heading.isFinite && pos.heading >= 0)
        ? pos.heading
        : null;
    final movementBearing = _lastMovementBearing;
    final routeBearing = _resolveForwardRouteBearing(pos, snap: snap);
    final reliableSnap = _hasReliableRouteSnapForBearing();
    final confidence = _lastNavConfidence;
    final progress = _lastNavRouteProgress;

    final policy = NavBearingPolicy.resolve(
      NavBearingPolicyInput(
        rawHeading: gpsHeading,
        routeBearing: routeBearing,
        movementBearing: movementBearing,
        lastBearing: _lastKnownBearing.isFinite && _lastKnownBearing > 0
            ? _lastKnownBearing
            : null,
        speedKmh: speedKmh,
        accuracyM: pos.accuracy.isFinite && pos.accuracy > 0
            ? pos.accuracy
            : null,
        routeConfidence: progress?.confidence ?? confidence?.routeScore,
        hasReliableSnap: reliableSnap,
        offRouteLikely: progress?.offRouteLikely ?? _offRouteLikely,
        trustBearing: confidence?.trustBearing ?? true,
        trustRouteSnap: reliableSnap,
        routeDeviationLikely: progress?.routeDeviationLikely ?? false,
        oppositeDirectionLikely: progress?.oppositeDirectionLikely ?? false,
        backwardProgressLikely: progress?.backwardProgressLikely ?? false,
        headingDeltaDeg: progress?.headingDeltaDeg,
        forwardProgress: progress?.forwardProgress ?? true,
      ),
    );

    final previous = _lastKnownBearing.isFinite && _lastKnownBearing > 0
        ? _lastKnownBearing
        : null;
    final bearing = NavBearingPolicy.stepToward(
      previous: previous,
      target: policy.targetBearing,
      maxStepDeg: policy.maxStepDeg,
    );
    _lastKnownBearing = bearing;

    final appliedDelta = previous == null
        ? policy.targetDeltaDeg
        : NavBearingSmoother.bearingDelta(previous, bearing);

    _logNavR11Bearing(
      source: policy.source,
      speedKmh: speedKmh,
      accuracyM: pos.accuracy.isFinite && pos.accuracy > 0
          ? pos.accuracy
          : null,
      confidence: progress?.confidence ?? confidence?.routeScore,
      deltaDeg: appliedDelta,
      appliedDeg: bearing,
      reason: policy.reason,
      headingDeltaDeg: progress?.headingDeltaDeg,
      routeDeviationLikely: progress?.routeDeviationLikely ?? false,
      oppositeDirectionLikely: progress?.oppositeDirectionLikely ?? false,
      backwardProgressLikely: progress?.backwardProgressLikely ?? false,
      offRouteLikely: progress?.offRouteLikely ?? _offRouteLikely,
      routeBearingAllowed: policy.routeBearingAllowed,
    );
    _logNavBounded(
      'NAV_BEARING',
      'speedKmh=${speedKmh.toStringAsFixed(1)} '
          'gpsHeading=${gpsHeading?.toStringAsFixed(1) ?? 'na'} '
          'routeBearing=${routeBearing?.toStringAsFixed(1) ?? 'na'} '
          'usedBearing=${bearing.toStringAsFixed(1)} source=${policy.source} '
          'deltaDeg=${appliedDelta?.toStringAsFixed(1) ?? 'na'}',
    );
    _logNavBounded(
      'NAV_OS_R2_BEARING',
      'source=${_r2BearingSourceLabel(policy.source)} '
          'delta=${(_lastR2BearingDeltaDeg ?? policy.targetDeltaDeg)?.toStringAsFixed(1) ?? 'na'} '
          'reversedGuard=$_lastR2ReversedGuard',
    );
    return (
      bearing: bearing,
      source: policy.source,
      gpsHeading: gpsHeading,
      movementBearing: movementBearing,
      routeBearing: routeBearing,
      bearingDeltaDeg: appliedDelta,
    );
  }

  double? _bearingFromPoints(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return driverBearingFromPoints(lat1, lon1, lat2, lon2);
  }

  Future<geo.Position?> _fetchCurrentPositionForRecenter() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GPS][RECENTER][SERVICE_DISABLED]');
      _toast(
        _tr(
          nl: 'Locatieservice staat uit. Zet GPS aan om te centreren.',
          en: 'Location service is disabled. Enable GPS to recenter.',
          fr: 'Le service de localisation est desactive. Activez le GPS pour recentrer.',
          es: 'El servicio de ubicacion esta desactivado. Activa el GPS para recentrar.',
        ),
      );
      return null;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      debugPrint('[GPS][RECENTER][PERMISSION_DENIED]');
      _toast(
        _tr(
          nl: 'Geen locatiepermissie. Geef toegang om te centreren.',
          en: 'Location permission denied. Grant access to recenter.',
          fr: 'Permission de localisation refusee. Autorisez-la pour recentrer.',
          es: 'Permiso de ubicacion denegado. Concedelo para recentrar.',
        ),
      );
      return null;
    }

    debugPrint('[GPS][RECENTER][FETCH_START]');
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      ).timeout(const Duration(seconds: 10));
      debugPrint(
        '[GPS][RECENTER][FETCH_OK] lat=${pos.latitude.toStringAsFixed(6)} lng=${pos.longitude.toStringAsFixed(6)}',
      );
      return pos;
    } catch (e) {
      debugPrint('[GPS][RECENTER][ERROR] $e');
      _toast(
        _tr(
          nl: 'GPS-positie ophalen mislukt. Probeer opnieuw.',
          en: 'Failed to get GPS position. Please try again.',
          fr: 'Impossible de recuperer la position GPS. Reessayez.',
          es: 'No se pudo obtener la posicion GPS. Intentalo de nuevo.',
        ),
      );
      return null;
    }
  }

  Future<void> _centerOnMe() async {
    debugPrint('[GPS][RECENTER][TAP]');
    geo.Position? pos = _lastPos;
    if (pos != null) {
      debugPrint('[GPS][RECENTER][CACHE_HIT]');
    } else {
      pos = await _fetchCurrentPositionForRecenter();
      if (pos == null) return;
      _lastPos = pos;
    }

    if (_mapSupported && _map != null && _driverPointManager != null) {
      await _updateDriverMarker(pos, moveCamera: false);
    }

    if (_liveRideActive) {
      if (mounted) {
        setState(() {
          _cameraMode = _CameraMode.follow;
          _followCar = true;
          _hasSwitchedToFollow = true;
          _allowOverviewCamera = false;
        });
      } else {
        _cameraMode = _CameraMode.follow;
        _followCar = true;
        _hasSwitchedToFollow = true;
        _allowOverviewCamera = false;
      }
      await _applyMapStyleForMode();
      _lastSmoothedCameraBearing = null;
      _updateRouteSnapState(pos);
      await _syncVisibleRouteLineWithProgress(pos);
      await _syncMapboxUserLocationPuckVisibility();
      await _followCameraTesla(
        pos,
        force: true,
        cameraReason: 'manual_recenter',
      );
      debugPrint('[GPS][RECENTER][FOLLOW_RESTORED]');
      return;
    }

    if (_cameraMode == _CameraMode.follow) {
      await _followCameraTesla(
        pos,
        force: true,
        cameraReason: 'manual_recenter',
      );
      return;
    }

    final p = _mbPoint(pos.longitude, pos.latitude);
    await _map?.flyTo(
      mb.CameraOptions(center: p, zoom: 13.5),
      mb.MapAnimationOptions(duration: 650),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  _ExternalNavTarget? _resolveExternalNavTarget() {
    if (_directRideDestinationPoint != null) {
      return _ExternalNavTarget(
        lat: _directRideDestinationPoint!.lat,
        lon: _directRideDestinationPoint!.lon,
      );
    }

    if (_routeCoords.isNotEmpty) {
      final destination = _routeCoords.last;
      return _ExternalNavTarget(lat: destination.lat, lon: destination.lon);
    }

    final bookingDestination = (_activeBooking?.to ?? '').trim();
    if (bookingDestination.isNotEmpty) {
      return _ExternalNavTarget(query: bookingDestination);
    }

    final directDestination = (_directRideDestinationText ?? '').trim();
    if (directDestination.isNotEmpty) {
      return _ExternalNavTarget(query: directDestination);
    }

    return null;
  }

  Future<void> _launchExternalNavUri(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Navigatie-app kon niet worden geopend.',
            en: 'Could not open navigation app.',
            fr: 'Impossible d’ouvrir l’application de navigation.',
            es: 'No se pudo abrir la aplicación de navegación.',
          ),
        ),
      ),
    );
  }

  Future<void> _openInGoogleMaps() async {
    final target = _resolveExternalNavTarget();
    if (target == null) return;
    Uri uri;
    if (target.hasCoordinates) {
      uri = Uri.https('www.google.com', '/maps/dir/', <String, String>{
        'api': '1',
        'destination': '${target.lat},${target.lon}',
      });
    } else if (target.hasQuery) {
      uri = Uri.https('www.google.com', '/maps/dir/', <String, String>{
        'api': '1',
        'destination': target.query!.trim(),
      });
    } else {
      return;
    }
    await _launchExternalNavUri(uri);
  }

  Future<void> _openInWaze() async {
    final target = _resolveExternalNavTarget();
    if (target == null) return;
    Uri uri;
    if (target.hasCoordinates) {
      uri = Uri.https('waze.com', '/ul', <String, String>{
        'll': '${target.lat},${target.lon}',
        'navigate': 'yes',
      });
    } else if (target.hasQuery) {
      uri = Uri.https('waze.com', '/ul', <String, String>{
        'q': target.query!.trim(),
        'navigate': 'yes',
      });
    } else {
      return;
    }
    await _launchExternalNavUri(uri);
  }

  Widget _buildCompactNavIconChip({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color navAccent,
    required Color navText,
    required Color navSurface,
    double size = 40,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: navSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: navAccent.withOpacity(0.72),
                width: 1.1,
              ),
            ),
            child: Icon(icon, size: 18, color: navText),
          ),
        ),
      ),
    );
  }

  ({Color accent, Color text, Color surface}) _navActionThemeColors() {
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    return (
      accent: isMidnightBlue
          ? _midnightBlueAccent()
          : (isMiddayGold ? const Color(0xFFE8C57E) : kFluxidiYellow),
      text: isMidnightBlue
          ? _midnightBlueTextPrimary()
          : (isMiddayGold ? _middayGoldTextPrimary() : Colors.white),
      surface: isMidnightBlue
          ? const Color(0xCC07111F)
          : (isMiddayGold ? const Color(0xCC2C2113) : const Color(0xCC0B1326)),
    );
  }

  /// NAV-UI-R6F: compact icon-only map actions rendered inside the bottom
  /// cockpit bar during route preview / navigation: recenter, satellite,
  /// offline, diagnostics, more (Google/Waze expand from "more").
  List<Widget> _buildCockpitSecondaryActions() {
    final hasExternal = _resolveExternalNavTarget() != null;
    final showNavMapTools =
        _cameraMode == _CameraMode.follow || _routeCoords.length >= 2;
    final showMapStyleToggle =
        kDriverMapSatelliteToggleEnabled && showNavMapTools;
    final showOffline = showNavMapTools;
    final showNavDiagExport = !kReleaseMode && showNavMapTools;
    final inFollowNav = _cameraMode == _CameraMode.follow;

    final colors = _navActionThemeColors();
    const iconSize = 44.0;

    if (inFollowNav &&
        showOffline &&
        kUseNavigationWorker &&
        _routeCoords.length >= 2) {
      unawaited(_maybeFetchOfflineCorridorMetadata());
    }

    final chips = <Widget>[
      _buildCompactNavIconChip(
        icon: Icons.my_location,
        tooltip: kCenterOnMeLabel,
        onPressed: _centerOnMe,
        navAccent: colors.accent,
        navText: colors.text,
        navSurface: colors.surface,
        size: iconSize,
      ),
    ];

    if (showMapStyleToggle) {
      final isSatellite = _driverMapVisualMode == DriverMapVisualMode.satellite;
      chips.add(
        _buildCompactNavIconChip(
          icon: isSatellite ? Icons.map_outlined : Icons.satellite_alt_outlined,
          tooltip: isSatellite
              ? _tr(
                  nl: 'Terug naar kaartweergave',
                  en: 'Back to map view',
                  fr: 'Retour à la carte',
                  es: 'Volver al mapa',
                )
              : _tr(
                  nl: 'Satellietweergave',
                  en: 'Satellite view',
                  fr: 'Vue satellite',
                  es: 'Vista satélite',
                ),
          onPressed: _toggleDriverMapVisualMode,
          navAccent: colors.accent,
          navText: colors.text,
          navSurface: colors.surface,
          size: iconSize,
        ),
      );
    }
    if (showOffline) {
      chips.add(
        _buildCompactNavIconChip(
          icon: Icons.wifi_off_rounded,
          tooltip: _tr(
            nl: 'Offline kaarten',
            en: 'Offline maps',
            fr: 'Cartes hors ligne',
            es: 'Mapas sin conexión',
          ),
          onPressed: _openOfflineMaps,
          navAccent: colors.accent,
          navText: colors.text,
          navSurface: colors.surface,
          size: iconSize,
        ),
      );
    }
    if (showNavDiagExport) {
      chips.add(
        _buildCompactNavIconChip(
          icon: Icons.bug_report_outlined,
          tooltip: _tr(
            nl: 'Deel navigatie-diagnose',
            en: 'Share nav diagnostics',
            fr: 'Partager diagnostic navigation',
            es: 'Compartir diagnostico de navegacion',
          ),
          onPressed: _shareNavDiagnostics,
          navAccent: colors.accent,
          navText: colors.text,
          navSurface: colors.surface,
          size: iconSize,
        ),
      );
    }
    if (hasExternal) {
      final moreExpanded = _navQuickActionsMoreExpanded;
      chips.add(
        _buildCompactNavIconChip(
          icon: moreExpanded ? Icons.close : Icons.more_horiz,
          tooltip: moreExpanded
              ? _tr(
                  nl: 'Minder acties',
                  en: 'Fewer actions',
                  fr: 'Moins d\u2019actions',
                  es: 'Menos acciones',
                )
              : _tr(
                  nl: 'Meer acties',
                  en: 'More actions',
                  fr: 'Plus d\u2019actions',
                  es: 'Mas acciones',
                ),
          onPressed: () {
            if (mounted) {
              setState(() {
                _navQuickActionsMoreExpanded = !_navQuickActionsMoreExpanded;
              });
            } else {
              _navQuickActionsMoreExpanded = !_navQuickActionsMoreExpanded;
            }
          },
          navAccent: colors.accent,
          navText: colors.text,
          navSurface: colors.surface,
          size: iconSize,
        ),
      );
      if (moreExpanded) {
        chips.add(
          _buildCompactNavIconChip(
            icon: Icons.map,
            tooltip: _tr(
              nl: 'Openen in Google Maps',
              en: 'Open in Google Maps',
              fr: 'Ouvrir dans Google Maps',
              es: 'Abrir en Google Maps',
            ),
            onPressed: _openInGoogleMaps,
            navAccent: colors.accent,
            navText: colors.text,
            navSurface: colors.surface,
            size: iconSize,
          ),
        );
        chips.add(
          _buildCompactNavIconChip(
            icon: Icons.alt_route,
            tooltip: _tr(
              nl: 'Openen in Waze',
              en: 'Open in Waze',
              fr: 'Ouvrir dans Waze',
              es: 'Abrir en Waze',
            ),
            onPressed: _openInWaze,
            navAccent: colors.accent,
            navText: colors.text,
            navSurface: colors.surface,
            size: iconSize,
          ),
        );
      }
    }
    return chips;
  }

  /// NAV-UI-R6F: R9 tunnel / GPS-reacquire status chip shown centered above
  /// the cockpit bar during follow navigation.
  Widget _buildCockpitR9StatusChip() {
    final r9 = _navR9OfflineReadiness();
    _logNavR9Offline(state: r9.state, reason: r9.reason);
    if (_cameraMode != _CameraMode.follow) return const SizedBox.shrink();
    if (!r9.showTunnelChip && !r9.showGpsReacquireChip) {
      return const SizedBox.shrink();
    }
    final colors = _navActionThemeColors();
    return _buildNavR9DataOffStatusChip(
      showTunnelChip: r9.showTunnelChip,
      showGpsReacquireChip: r9.showGpsReacquireChip,
      navText: colors.text,
      navSurface: colors.surface,
      navAccent: colors.accent,
    );
  }

  // -------------------------------
  // ROUTE (Overview -> Follow)
  // -------------------------------

  Future<void> _buildOverviewRoute(BookingItem b) async {
    final epoch = _routeCleanupEpoch;
    final expectedBookingId = b.bookingId;
    if (!_isRouteTaskStillValid(
      epoch: epoch,
      expectedBookingId: expectedBookingId,
    )) {
      return;
    }
    if (!_mapSupported || _map == null) return;
    final endpoints = _extractPreviewEndpoints(b);
    final storedPickup = _usableNavLonLat(endpoints.pickup);
    final storedDropoff = _usableNavLonLat(endpoints.dropoff);
    final pickupText = (b.from ?? '').trim();
    final dropoffText = (b.to ?? '').trim();
    if (pickupText.isEmpty &&
        storedPickup == null &&
        dropoffText.isEmpty &&
        storedDropoff == null) {
      return;
    }
    if ((pickupText.isEmpty && storedPickup == null) ||
        (dropoffText.isEmpty && storedDropoff == null)) {
      return;
    }

    try {
      // Preview must always represent booked ride path: pickup -> destination.
      // Never use current GPS here.
      await _clearRouteAndPinAnnotationsOnly();

      if (storedPickup != null && storedDropoff != null) {
        debugPrint('[NAV_COORD] overview=stored_both');
        final route = await _directionsRoute(storedPickup, storedDropoff);
        final coords = route.$1;
        if (coords.length >= 2 &&
            _isRouteTaskStillValid(
              epoch: epoch,
              expectedBookingId: expectedBookingId,
            )) {
          setState(() {
            _routeCoords = coords;
            _routeKm = route.$2 / 1000.0;
            _routeDurationSec = route.$3;
            _routePhase = _RideRoutePhase.trip;
          });
          await _drawPins(storedPickup, storedDropoff);
          await _drawRouteLine(coords);
          final allowFit =
              _allowOverviewCamera &&
              _cameraMode == _CameraMode.overview &&
              _activeTripId == null;
          if (allowFit) {
            await _fitBoundsToRoute(coords);
          }
          return;
        }
      }

      // Prefer server-side routing (Worker) so the app never needs to call Mapbox Directions directly.
      await _tryWorkerRouteFallback(
        fromText: pickupText,
        toText: dropoffText,
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      );
      if (_routeCoords.length >= 2) return;

      // Fallback: direct Mapbox REST (dev only). If MAPBOX_TOKEN isn't provided, we stop here.
      if (kMapboxToken.trim().isEmpty) {
        await _tryWorkerRouteFallback(
          fromText: pickupText,
          toText: dropoffText,
          epoch: epoch,
          expectedBookingId: expectedBookingId,
        );
        return;
      }

      final fromLL = await _resolvePickupLonLat(b);
      final toLL = await _resolveDropoffLonLat(b);

      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      final distanceMeters = route.$2;
      final durationSec = route.$3;

      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }

      setState(() {
        _routeCoords = coords;
        _routeKm = distanceMeters / 1000.0;
        _routeDurationSec = durationSec;
        _routePhase = _RideRoutePhase.trip;
      });
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
      final allowFit =
          _allowOverviewCamera &&
          _cameraMode == _CameraMode.overview &&
          _activeTripId == null;
      if (allowFit) {
        await _fitBoundsToRoute(coords);
      }
    } on _UnauthorizedMapbox catch (_) {
      _toast('Mapbox REST token refused (401) — using Worker route instead.');
      await _tryWorkerRouteFallback(
        fromText: b.from!,
        toText: b.to!,
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      );
    } catch (e) {
      _toast('Route overview failed: $e');
      await _tryWorkerRouteFallback(
        fromText: b.from!,
        toText: b.to!,
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      );
    }
  }

  Future<void> _tryWorkerRouteFallback({
    required String fromText,
    required String toText,
    required int epoch,
    required String expectedBookingId,
  }) async {
    try {
      final uri = Uri.parse('$kWorkerBaseUrl$kWorkerRoutePath');
      final payload = {'from': fromText, 'to': toText};

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 404) {
        _toast(
          'Route via Worker not available yet (404). Implement $kWorkerRoutePath to avoid exposing Mapbox token.',
        );
        return;
      }

      if (res.statusCode != 200) {
        throw Exception('Worker route HTTP ${res.statusCode}: ${res.body}');
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;

      final coordsAny =
          (j['coords'] ?? j['coordinates'] ?? j['route_coords'] ?? j['points']);
      List<dynamic> raw;
      if (coordsAny is List) {
        raw = coordsAny;
      } else if (j['geometry'] is Map<String, dynamic>) {
        raw = (j['geometry']['coordinates'] as List<dynamic>? ?? []);
      } else {
        raw = const [];
      }

      final out = <_LonLat>[];
      for (final c in raw) {
        if (c is List && c.length >= 2) {
          out.add(_LonLat((c[0] as num).toDouble(), (c[1] as num).toDouble()));
        }
      }

      if (out.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }

      final dist =
          (j['distance_m'] ?? j['distanceMeters'] ?? j['distance'] ?? 0) as num;
      final dur =
          (j['duration_s'] ?? j['durationSec'] ?? j['duration'] ?? 0) as num;

      final fromLL = out.first;
      final toLL = out.last;

      setState(() {
        _routeCoords = out;
        _routeKm = dist.toDouble() / 1000.0;
        _routeDurationSec = dur.toInt();
        _routePhase = _RideRoutePhase.trip;
      });
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(out);
      final allowFit =
          _allowOverviewCamera &&
          _cameraMode == _CameraMode.overview &&
          _activeTripId == null;
      if (allowFit) {
        await _fitBoundsToRoute(out);
      }
    } catch (e) {
      _toast('Worker route failed: $e');
    }
  }

  Future<_LonLat> _geocodeOne(String query) async {
    final q = Uri.encodeComponent(query);
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$q.json'
      '?access_token=$kMapboxToken&limit=1&country=BE&language=nl',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 12));

    if (res.statusCode == 401) throw _UnauthorizedMapbox('geocoding');
    if (res.statusCode != 200) {
      throw Exception('Geocode HTTP ${res.statusCode}');
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final feats = (j['features'] as List<dynamic>? ?? []);
    if (feats.isEmpty) throw Exception('No geocode result for "$query"');
    final center =
        (feats.first as Map<String, dynamic>)['center'] as List<dynamic>;
    final lon = (center[0] as num).toDouble();
    final lat = (center[1] as num).toDouble();
    return _LonLat(lon, lat);
  }

  Future<(List<_LonLat>, double, int)> _directionsRoute(
    _LonLat from,
    _LonLat to,
  ) async {
    final workerParsed = await _tryNavigationWorkerDirectionsRoute(from, to);
    if (workerParsed != null) {
      _applyParsedNavRouteSteps(workerParsed);
      return (
        workerParsed.coords,
        workerParsed.distanceMeters,
        workerParsed.durationSeconds,
      );
    }

    final lang = _mapboxDirectionsLanguageCode();
    final uri = buildDriverDirectionsUri(
      from: from,
      to: to,
      languageCode: lang,
      accessToken: kMapboxToken,
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 15));

    if (res.statusCode == 401) throw _UnauthorizedMapbox('directions');
    if (res.statusCode != 200) {
      throw Exception('Directions HTTP ${res.statusCode}');
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final parsed = parseDriverDirectionsResponse(
      response: j,
      localizeInstruction: _localizeNavInstructionMvp,
      distanceAlongRouteForCoords: _distanceAlongRouteForCoords,
    );
    _applyParsedNavRouteSteps(parsed);
    return (parsed.coords, parsed.distanceMeters, parsed.durationSeconds);
  }

  String _mapboxDirectionsLanguageCode() {
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.fr) return 'fr';
    if (lang == AppLanguage.es) return 'es';
    if (lang == AppLanguage.en) return 'en';
    return 'nl';
  }

  String _navigationWorkerCountryCode() {
    const allowed = {'BE', 'NL', 'FR', 'ES', 'PT'};
    String? normalize(dynamic raw) {
      final text = raw?.toString().trim().toUpperCase();
      if (text == null || text.isEmpty) return null;
      if (allowed.contains(text)) return text;
      if (text.length >= 2) {
        final short = text.substring(0, 2);
        if (allowed.contains(short)) return short;
      }
      return null;
    }

    final booking = _activeBooking;
    if (booking != null) {
      final details = booking.details;
      final paths = <List<String>>[
        ['quote', 'inputs', 'country'],
        ['quote', 'country'],
        ['booking', 'country'],
        ['customer_country'],
        ['country'],
        ['record', 'payload', 'country'],
      ];
      for (final path in paths) {
        dynamic current = details;
        for (final key in path) {
          if (current is Map && current.containsKey(key)) {
            current = current[key];
          } else {
            current = null;
            break;
          }
        }
        final code = normalize(current);
        if (code != null) return code;
      }
    }
    return 'BE';
  }

  Future<DriverRouteParseResult?> _tryNavigationWorkerDirectionsRoute(
    _LonLat from,
    _LonLat to,
  ) async {
    if (!kUseNavigationWorker) return null;
    final baseUrl = kNavigationWorkerBaseUrl.trim();
    if (baseUrl.isEmpty) return null;

    final client = DriverNavigationWorkerClient(baseUrl: baseUrl);
    final country = _navigationWorkerCountryCode();
    final tripId = _activeTripId?.trim();

    NavigationWorkerRouteResult? workerResult;
    try {
      if (_isRerouting) {
        workerResult = await client.reroute(
          current: from,
          destination: to,
          country: country,
          tripId: tripId,
          reason: _rerouteReason ?? 'unknown',
        );
      } else {
        workerResult = await client.route(
          origin: from,
          destination: to,
          country: country,
          tripId: tripId,
        );
      }
    } catch (_) {
      debugPrint(
        '[CLOUD_NAV_2] endpoint=${_isRerouting ? 'reroute' : 'route'} '
        'result=fallback reason=worker_exception country=$country',
      );
      return null;
    }

    if (workerResult == null || !workerResult.isValid) {
      debugPrint(
        '[CLOUD_NAV_2] endpoint=${_isRerouting ? 'reroute' : 'route'} '
        'result=fallback reason=invalid_worker_payload country=$country',
      );
      return null;
    }

    final parsed = parseDriverDirectionsResponse(
      response: workerResult.toMapboxDirectionsShape(),
      localizeInstruction: _localizeNavInstructionMvp,
      distanceAlongRouteForCoords: _distanceAlongRouteForCoords,
    );
    if (parsed.coords.length < 2) {
      debugPrint(
        '[CLOUD_NAV_2] endpoint=${_isRerouting ? 'reroute' : 'route'} '
        'result=fallback reason=parse_empty country=$country',
      );
      return null;
    }

    return parsed;
  }

  void _applyParsedNavRouteSteps(DriverRouteParseResult parsed) {
    final navSteps = parsed.navSteps;
    _routeSteps = navSteps;
    _nextStepIndex = 0;
    // NAV-R12-E2: fresh route generation — the instruction re-resolves from
    // index 0 against the new geometry on the next fix.
    _routeStepsVersion += 1;
    _logNavR12Banner(state: 're_resolved', reason: 'route_steps_applied');
    if (navSteps.isNotEmpty) {
      _nextNavInstruction = navSteps.first.instruction;
      _nextNavStreet = navSteps.first.street;
      _nextNavDistanceM = null;
      _nextNavType = navSteps.first.type;
      _nextNavModifier = navSteps.first.modifier;
      _navInstructionSnapshot = null;
    } else {
      _nextNavInstruction = null;
      _nextNavStreet = null;
      _nextNavDistanceM = null;
      _nextNavType = null;
      _nextNavModifier = null;
      _navInstructionSnapshot = NavInstructionSnapshot.none;
    }
    debugPrint(
      '[NAV_E1] steps=${navSteps.length} bannerSteps=${parsed.stepsWithBannerCount} '
      'laneSteps=${parsed.stepsWithLaneGuidanceCount}',
    );
  }

  String _localizeNavInstructionMvp(String raw) {
    return localizeDriverNavInstructionMvp(
      raw: raw,
      languageCode: _mapboxDirectionsLanguageCode(),
      tr: _tr,
    );
  }

  String _nextRidePreviewCacheKey(BookingItem booking) {
    final bookingRowKey = booking.rowKey.trim();
    final from = (booking.from ?? '').trim().toLowerCase();
    final to = (booking.to ?? '').trim().toLowerCase();
    final pickupIso = (booking.pickupIso ?? '').trim();
    return '$bookingRowKey|$from|$to|$pickupIso';
  }

  Future<_RoutePreviewData?> _nextRidePreviewFuture(BookingItem booking) {
    final key = _nextRidePreviewCacheKey(booking);
    final cached = _nextRidePreviewCache[key];
    if (cached != null) return cached;
    final future = _loadNextRideRoutePreview(booking);
    _nextRidePreviewCache[key] = future;
    if (_nextRidePreviewCache.length > 16) {
      final oldestKey = _nextRidePreviewCache.keys.first;
      _nextRidePreviewCache.remove(oldestKey);
    }
    return future;
  }

  num? _previewNum(dynamic raw) {
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw.trim().replaceAll(',', '.'));
    return null;
  }

  _LonLat? _previewPointFromDetailPaths(
    Map<String, dynamic> details,
    List<List<String>> latPaths,
    List<List<String>> lonPaths,
  ) {
    num? lat;
    num? lon;
    for (final path in latPaths) {
      final v = _previewNum(_getNested(details, path));
      if (v != null) {
        lat = v;
        break;
      }
    }
    for (final path in lonPaths) {
      final v = _previewNum(_getNested(details, path));
      if (v != null) {
        lon = v;
        break;
      }
    }
    if (lat == null || lon == null) return null;
    return _usableNavLonLat(_LonLat(lon.toDouble(), lat.toDouble()));
  }

  /// NAV-B: stored booking coordinates are preferred over geocoded address text.
  _LonLat? _usableNavLonLat(_LonLat? point) {
    if (point == null) return null;
    if (!point.lat.isFinite || !point.lon.isFinite) return null;
    if (point.lat.abs() > 90 || point.lon.abs() > 180) return null;
    if (point.lat == 0 && point.lon == 0) return null;
    return point;
  }

  Future<_LonLat> _resolvePickupLonLat(BookingItem booking) async {
    final stored = _usableNavLonLat(_extractPreviewEndpoints(booking).pickup);
    if (stored != null) {
      debugPrint('[NAV_COORD] pickup=stored');
      return stored;
    }
    final text = (booking.from ?? '').trim();
    if (text.isEmpty) {
      throw Exception('Pickup coordinates and address are missing.');
    }
    debugPrint('[NAV_COORD] pickup=geocode');
    return _geocodeOne(text);
  }

  Future<_LonLat> _resolveDropoffLonLat(BookingItem booking) async {
    final stored = _usableNavLonLat(_extractPreviewEndpoints(booking).dropoff);
    if (stored != null) {
      debugPrint('[NAV_COORD] dropoff=stored');
      return stored;
    }
    final text = (booking.to ?? '').trim();
    if (text.isEmpty) {
      throw Exception('Dropoff coordinates and address are missing.');
    }
    debugPrint('[NAV_COORD] dropoff=geocode');
    return _geocodeOne(text);
  }

  ({_LonLat? pickup, _LonLat? dropoff}) _extractPreviewEndpoints(
    BookingItem booking,
  ) {
    final d = booking.details;
    final pickup = _previewPointFromDetailPaths(
      d,
      const [
        ['pickup_lat'],
        ['pickupLat'],
        ['from_lat'],
        ['fromLat'],
        ['pickup', 'lat'],
        ['from', 'lat'],
        ['record', 'pickup_lat'],
        ['record', 'pickup', 'lat'],
        ['record', 'booking', 'pickup_lat'],
        ['record', 'booking', 'pickup', 'lat'],
        ['record', 'booking_details', 'pickup_lat'],
        ['record', 'booking_details', 'pickup', 'lat'],
        ['payload', 'pickup_lat'],
        ['payload', 'pickup', 'lat'],
        ['quote', 'pickup', 'lat'],
        ['quote', 'origin', 'lat'],
      ],
      const [
        ['pickup_lon'],
        ['pickupLng'],
        ['pickupLon'],
        ['from_lon'],
        ['fromLng'],
        ['fromLon'],
        ['pickup', 'lon'],
        ['pickup', 'lng'],
        ['from', 'lon'],
        ['from', 'lng'],
        ['record', 'pickup_lon'],
        ['record', 'pickup', 'lon'],
        ['record', 'pickup', 'lng'],
        ['record', 'booking', 'pickup_lon'],
        ['record', 'booking', 'pickup', 'lon'],
        ['record', 'booking', 'pickup', 'lng'],
        ['record', 'booking_details', 'pickup_lon'],
        ['record', 'booking_details', 'pickup', 'lon'],
        ['record', 'booking_details', 'pickup', 'lng'],
        ['payload', 'pickup_lon'],
        ['payload', 'pickup', 'lon'],
        ['payload', 'pickup', 'lng'],
        ['quote', 'pickup', 'lon'],
        ['quote', 'pickup', 'lng'],
        ['quote', 'origin', 'lon'],
        ['quote', 'origin', 'lng'],
      ],
    );
    final dropoff = _previewPointFromDetailPaths(
      d,
      const [
        ['dropoff_lat'],
        ['dropoffLat'],
        ['to_lat'],
        ['toLat'],
        ['destination_lat'],
        ['destinationLat'],
        ['dropoff', 'lat'],
        ['to', 'lat'],
        ['destination', 'lat'],
        ['record', 'dropoff_lat'],
        ['record', 'dropoff', 'lat'],
        ['record', 'booking', 'dropoff_lat'],
        ['record', 'booking', 'dropoff', 'lat'],
        ['record', 'booking_details', 'dropoff_lat'],
        ['record', 'booking_details', 'dropoff', 'lat'],
        ['payload', 'dropoff_lat'],
        ['payload', 'dropoff', 'lat'],
        ['quote', 'dropoff', 'lat'],
        ['quote', 'destination', 'lat'],
      ],
      const [
        ['dropoff_lon'],
        ['dropoffLng'],
        ['dropoffLon'],
        ['to_lon'],
        ['toLng'],
        ['toLon'],
        ['destination_lon'],
        ['destinationLng'],
        ['destinationLon'],
        ['dropoff', 'lon'],
        ['dropoff', 'lng'],
        ['to', 'lon'],
        ['to', 'lng'],
        ['destination', 'lon'],
        ['destination', 'lng'],
        ['record', 'dropoff_lon'],
        ['record', 'dropoff', 'lon'],
        ['record', 'dropoff', 'lng'],
        ['record', 'booking', 'dropoff_lon'],
        ['record', 'booking', 'dropoff', 'lon'],
        ['record', 'booking', 'dropoff', 'lng'],
        ['record', 'booking_details', 'dropoff_lon'],
        ['record', 'booking_details', 'dropoff', 'lon'],
        ['record', 'booking_details', 'dropoff', 'lng'],
        ['payload', 'dropoff_lon'],
        ['payload', 'dropoff', 'lon'],
        ['payload', 'dropoff', 'lng'],
        ['quote', 'dropoff', 'lon'],
        ['quote', 'dropoff', 'lng'],
        ['quote', 'destination', 'lon'],
        ['quote', 'destination', 'lng'],
      ],
    );
    return (pickup: pickup, dropoff: dropoff);
  }

  Future<List<_LonLat>> _workerRouteForPreview({
    required String fromText,
    required String toText,
  }) async {
    if (fromText.trim().isEmpty || toText.trim().isEmpty)
      return const <_LonLat>[];
    final uri = Uri.parse('$kWorkerBaseUrl$kWorkerRoutePath');
    final payload = <String, dynamic>{
      'from': fromText.trim(),
      'to': toText.trim(),
    };
    final res = await http
        .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const <_LonLat>[];
    final j = jsonDecode(res.body);
    if (j is! Map<String, dynamic>) return const <_LonLat>[];
    final coordsAny =
        (j['coords'] ?? j['coordinates'] ?? j['route_coords'] ?? j['points']);
    List<dynamic> raw = const <dynamic>[];
    if (coordsAny is List<dynamic>) {
      raw = coordsAny;
    } else if (j['geometry'] is Map<String, dynamic>) {
      raw =
          (j['geometry']['coordinates'] as List<dynamic>? ?? const <dynamic>[]);
    }
    final out = <_LonLat>[];
    for (final c in raw) {
      if (c is List && c.length >= 2) {
        final lon = _previewNum(c[0])?.toDouble();
        final lat = _previewNum(c[1])?.toDouble();
        if (lon != null && lat != null) out.add(_LonLat(lon, lat));
      }
    }
    return out.length >= 2 ? out : const <_LonLat>[];
  }

  Future<List<_LonLat>> _mapboxRouteForPreview({
    required _LonLat from,
    required _LonLat to,
  }) async {
    if (kMapboxToken.trim().isEmpty) return const <_LonLat>[];
    final coords = '${from.lon},${from.lat};${to.lon},${to.lat}';
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
      '?alternatives=false&geometries=geojson&overview=full'
      '&access_token=$kMapboxToken',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const <_LonLat>[];
    final j = jsonDecode(res.body);
    if (j is! Map<String, dynamic>) return const <_LonLat>[];
    final routes = (j['routes'] as List<dynamic>? ?? const <dynamic>[]);
    if (routes.isEmpty) return const <_LonLat>[];
    final r0 = routes.first;
    if (r0 is! Map<String, dynamic>) return const <_LonLat>[];
    final geometry =
        (r0['geometry'] as Map<String, dynamic>? ?? const <String, dynamic>{});
    final line =
        (geometry['coordinates'] as List<dynamic>? ?? const <dynamic>[]);
    final out = <_LonLat>[];
    for (final c in line) {
      if (c is List && c.length >= 2) {
        final lon = _previewNum(c[0])?.toDouble();
        final lat = _previewNum(c[1])?.toDouble();
        if (lon != null && lat != null) out.add(_LonLat(lon, lat));
      }
    }
    return out.length >= 2 ? out : const <_LonLat>[];
  }

  List<_LonLat> _downsamplePreviewRoute(
    List<_LonLat> coords, {
    int maxPoints = 100,
  }) {
    if (coords.length <= maxPoints) return coords;
    final out = <_LonLat>[coords.first];
    final stride = (coords.length - 2) / (maxPoints - 2);
    var cursor = 1.0;
    while (out.length < maxPoints - 1) {
      final idx = cursor.round().clamp(1, coords.length - 2);
      out.add(coords[idx]);
      cursor += stride;
    }
    out.add(coords.last);
    return out;
  }

  String _encodePolyline5(List<_LonLat> points) {
    if (points.isEmpty) return '';
    final sb = StringBuffer();
    var lastLat = 0;
    var lastLon = 0;
    void encodeDelta(int delta) {
      var v = delta < 0 ? ~(delta << 1) : (delta << 1);
      while (v >= 0x20) {
        sb.writeCharCode((0x20 | (v & 0x1f)) + 63);
        v >>= 5;
      }
      sb.writeCharCode(v + 63);
    }

    for (final p in points) {
      final lat = (p.lat * 1e5).round();
      final lon = (p.lon * 1e5).round();
      encodeDelta(lat - lastLat);
      encodeDelta(lon - lastLon);
      lastLat = lat;
      lastLon = lon;
    }
    return sb.toString();
  }

  String _buildStaticRoutePreviewUrl({
    required List<_LonLat> route,
    required _LonLat pickup,
    required _LonLat dropoff,
  }) {
    final compact = _downsamplePreviewRoute(route, maxPoints: 92);
    final polyline = Uri.encodeComponent(_encodePolyline5(compact));
    final overlays =
        'pin-s-a+f4c542(${pickup.lon},${pickup.lat}),'
        'pin-s-b+ff5a4f(${dropoff.lon},${dropoff.lat}),'
        'path-5+2d8cff-0.86($polyline)';
    return 'https://api.mapbox.com/styles/v1/mapbox/navigation-night-v1/static/'
        '$overlays/auto/720x280?padding=34,22,34,22&access_token=$kMapboxToken';
  }

  Future<_RoutePreviewData?> _loadNextRideRoutePreview(
    BookingItem booking,
  ) async {
    if (kMapboxToken.trim().isEmpty) return null;
    final fromText = (booking.from ?? '').trim();
    final toText = (booking.to ?? '').trim();
    if (fromText.isEmpty || toText.isEmpty) return null;

    final endpoints = _extractPreviewEndpoints(booking);
    _LonLat? pickup = endpoints.pickup;
    _LonLat? dropoff = endpoints.dropoff;

    List<_LonLat> routeCoords = await _workerRouteForPreview(
      fromText: fromText,
      toText: toText,
    );
    if (routeCoords.isNotEmpty) {
      pickup ??= routeCoords.first;
      dropoff ??= routeCoords.last;
    }

    if ((pickup == null || dropoff == null) && kMapboxToken.trim().isNotEmpty) {
      try {
        pickup ??= await _geocodeOne(fromText);
        dropoff ??= await _geocodeOne(toText);
      } catch (_) {}
    }
    if (pickup == null || dropoff == null) return null;

    if (routeCoords.length < 2) {
      routeCoords = await _mapboxRouteForPreview(from: pickup, to: dropoff);
    }
    if (routeCoords.length < 2) return null;

    final staticUrl = _buildStaticRoutePreviewUrl(
      route: routeCoords,
      pickup: pickup,
      dropoff: dropoff,
    );
    return _RoutePreviewData(
      staticMapUrl: staticUrl,
      routePointCount: routeCoords.length,
    );
  }

  Widget _buildNextRideRoutePreview(BookingItem booking, {double? height}) {
    final future = _nextRidePreviewFuture(booking);
    return Container(
      height: height ?? 136,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0E1012),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x66FFD36A)),
      ),
      child: FutureBuilder<_RoutePreviewData?>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final data = snap.data;
          if (data == null || data.staticMapUrl.trim().isEmpty) {
            return Center(
              child: Text(
                _tr(
                  nl: 'Route-preview niet beschikbaar',
                  en: 'Route preview unavailable',
                  fr: "Apercu d'itineraire indisponible",
                  es: 'Vista previa de ruta no disponible',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.2,
                ),
              ),
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                data.staticMapUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    _tr(
                      nl: 'Route-preview niet beschikbaar',
                      en: 'Route preview unavailable',
                      fr: "Apercu d'itineraire indisponible",
                      es: 'Vista previa de ruta no disponible',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.2,
                    ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.black.withOpacity(0.36),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _navDistanceText(double meters) {
    return driverNavDistanceText(meters);
  }

  bool _navTypeIsArrival(String? type) {
    return driverNavTypeIsArrival(type);
  }

  bool _navTypeIsRoundabout(String? type) {
    return driverNavTypeIsRoundabout(type);
  }

  String _shortNavAction(String instruction, String? type, String? modifier) {
    return driverShortNavAction(instruction, type, modifier, tr: _tr);
  }

  IconData _maneuverIconData(
    String? type,
    String? modifier,
    String instruction,
  ) {
    return driverManeuverIconData(type, modifier, instruction);
  }

  Future<void> _drawPins(_LonLat pickup, _LonLat dropoff) async {
    final mgr = _pinsPointManager;
    if (mgr == null) return;
    final now = DateTime.now();
    final signature = driverPinsDrawSignature(pickup: pickup, dropoff: dropoff);
    if (driverShouldSkipDraw(
      signature: signature,
      lastSignature: _lastPinsDrawSignature,
      lastDrawAt: _lastPinsDrawAt,
      debounce: _routeDrawDebounce,
      now: now,
    )) {
      return;
    }
    _lastPinsDrawSignature = signature;
    _lastPinsDrawAt = now;

    try {
      if (_pickupPin != null) await mgr.delete(_pickupPin!);
      if (_dropoffPin != null) await mgr.delete(_dropoffPin!);
    } catch (_) {}

    _pickupPin = await mgr.create(
      mb.PointAnnotationOptions(
        geometry: _mbPoint(pickup.lon, pickup.lat),
        iconSize: 1.1,
      ),
    );

    _dropoffPin = await mgr.create(
      mb.PointAnnotationOptions(
        geometry: _mbPoint(dropoff.lon, dropoff.lat),
        iconSize: 1.1,
      ),
    );
  }

  Future<void> _drawRouteLine(
    List<_LonLat> coords, {
    bool force = false,
    List<_LonLat>? completedCoords,
  }) async {
    final mgr = _routeLineManager;
    if (mgr == null) return;
    if (coords.length < 2) return;
    final now = DateTime.now();
    final signature = driverRouteDrawSignature(coords);
    if (driverShouldSkipDraw(
      signature: signature,
      lastSignature: _lastRouteDrawSignature,
      lastDrawAt: _lastRouteDrawAt,
      debounce: _routeDrawDebounce,
      force: force,
      now: now,
    )) {
      return;
    }
    _lastRouteDrawSignature = signature;
    _lastRouteDrawAt = now;
    _routeRedrawCountThisMinute += 1;

    try {
      if (_routeLineOutline != null) await mgr.delete(_routeLineOutline!);
      if (_routeLine != null) await mgr.delete(_routeLine!);
      if (_routeLineCompleted != null) await mgr.delete(_routeLineCompleted!);
    } catch (_) {}
    _routeLineCompleted = null;

    final geometry = mb.LineString(
      coordinates: coords.map((c) => mb.Position(c.lon, c.lat)).toList(),
    );

    // NAV-OS-R2: muted grey line for the already-driven section behind the taxi.
    if (completedCoords != null && completedCoords.length >= 2) {
      _routeLineCompleted = await mgr.create(
        mb.PolylineAnnotationOptions(
          geometry: mb.LineString(
            coordinates: completedCoords
                .map((c) => mb.Position(c.lon, c.lat))
                .toList(),
          ),
          lineWidth: kDriverRouteLineCompletedWidth,
          lineOpacity: kDriverRouteLineCompletedOpacity,
          lineColor: kDriverRouteLineCompletedColor,
        ),
      );
    }

    // Dark underlay for contrast on light navigation / satellite maps.
    _routeLineOutline = await mgr.create(
      mb.PolylineAnnotationOptions(
        geometry: geometry,
        lineWidth: kDriverRouteLineOutlineWidth,
        lineOpacity: kDriverRouteLineOutlineOpacity,
        lineColor: kDriverRouteLineOutlineColor,
      ),
    );

    _routeLine = await mgr.create(
      mb.PolylineAnnotationOptions(
        geometry: geometry,
        lineWidth: kDriverRouteLineWidth,
        lineOpacity: kDriverRouteLineOpacity,
        lineColor: kDriverRouteLineColor,
      ),
    );
    await _syncMapboxUserLocationPuckVisibility();
  }

  Future<void> _fitBoundsToRoute(List<_LonLat> coords) async {
    final skip =
        _cameraMode == _CameraMode.follow ||
        _activeTripId != null ||
        !_allowOverviewCamera;
    if (_map == null || coords.isEmpty) return;
    if (skip) return;

    double minLon = coords.first.lon, maxLon = coords.first.lon;
    double minLat = coords.first.lat, maxLat = coords.first.lat;
    for (final c in coords) {
      if (c.lon < minLon) minLon = c.lon;
      if (c.lon > maxLon) maxLon = c.lon;
      if (c.lat < minLat) minLat = c.lat;
      if (c.lat > maxLat) maxLat = c.lat;
    }

    final topPad = MediaQuery.of(context).padding.top + 86;
    final bottomPad = MediaQuery.of(context).padding.bottom + 210;

    try {
      final cam = await _map!.cameraForCoordinateBounds(
        mb.CoordinateBounds(
          southwest: _mbPoint(minLon, minLat),
          northeast: _mbPoint(maxLon, maxLat),
          infiniteBounds: false,
        ),
        mb.MbxEdgeInsets(top: topPad, left: 40, bottom: bottomPad, right: 40),
        null,
        null,
        null,
        null,
      );
      await _map!.flyTo(cam, mb.MapAnimationOptions(duration: 900));
    } catch (_) {
      final center = _mbPoint((minLon + maxLon) / 2, (minLat + maxLat) / 2);
      await _map!.flyTo(
        mb.CameraOptions(center: center, zoom: 12.5),
        mb.MapAnimationOptions(duration: 900),
      );
    }
  }

  void _markBootFirstLoadDone() {
    if (_bootFirstLoadDone) return;
    _bootFirstLoadDone = true;
    _maybeHideBootSplash();
  }

  void _maybeHideBootSplash() {
    if (!_bootSplashVisible) return;
    if (!_bootMinElapsed) return;
    if (!_bootFirstLoadDone) return;
    if (!mounted) return;
    setState(() {
      _bootSplashVisible = false;
      _showBootSplash = false;
    });
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
      filled: true,
      fillColor: Colors.black.withOpacity(0.35),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: kGlow, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Future<List<_PlaceSuggestion>> _fetchPlaceSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty || kMapboxToken.trim().isEmpty) return <_PlaceSuggestion>[];
    final encoded = Uri.encodeComponent(q);
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$encoded.json'
      '?autocomplete=true&limit=6&country=be&language=nl&access_token=$kMapboxToken',
    );
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return <_PlaceSuggestion>[];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final feats = (data['features'] as List<dynamic>? ?? const <dynamic>[]);
      final out = <_PlaceSuggestion>[];
      for (final f in feats) {
        final m = f as Map<String, dynamic>;
        final label = (m['place_name'] as String?) ?? '';
        final center = (m['center'] as List<dynamic>?);
        if (label.trim().isEmpty) continue;
        double? lon;
        double? lat;
        if (center != null && center.length >= 2) {
          lon = (center[0] as num?)?.toDouble();
          lat = (center[1] as num?)?.toDouble();
        }
        out.add(_PlaceSuggestion(label: label, lon: lon, lat: lat));
      }
      return out;
    } catch (_) {
      return <_PlaceSuggestion>[];
    }
  }

  void _onFromChanged(String v) {
    _fromDebounce?.cancel();
    _fromDebounce = Timer(const Duration(milliseconds: 220), () async {
      final list = await _fetchPlaceSuggestions(v);
      if (!mounted) return;
      setState(() => _fromSuggestions = list);
    });
  }

  void _onToChanged(String v) {
    _toDebounce?.cancel();
    _toDebounce = Timer(const Duration(milliseconds: 220), () async {
      final list = await _fetchPlaceSuggestions(v);
      if (!mounted) return;
      setState(() => _toSuggestions = list);
    });
  }

  Future<void> _useCurrentLocationAsFrom() async {
    try {
      final perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        final req = await geo.Geolocator.requestPermission();
        if (req == geo.LocationPermission.denied ||
            req == geo.LocationPermission.deniedForever)
          return;
      }
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      );
      _manualFromPoint = mb.Point(
        coordinates: mb.Position(pos.longitude, pos.latitude),
      );
      _manualFromCtrl.text = 'Mijn locatie';
      setState(() {
        _fromSuggestions = <_PlaceSuggestion>[];
      });
    } catch (_) {}
  }

  Widget _suggestionList({
    required List<_PlaceSuggestion> items,
    required void Function(_PlaceSuggestion) onPick,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F1C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x44FFD54A)),
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0x22000000)),
        itemBuilder: (_, i) {
          final s = items[i];
          return ListTile(
            dense: true,
            title: Text(
              s.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () => onPick(s),
          );
        },
      ),
    );
  }

  Future<void> _startManualTrip() async {
    final from = _manualFromCtrl.text.trim();
    final to = _manualToCtrl.text.trim();
    if (from.isEmpty || to.isEmpty) {
      _toast('Vul zowel "Van" als "Naar" in.');
      return;
    }

    final id = 'MANUAL-${DateTime.now().millisecondsSinceEpoch}';
    final b = BookingItem(
      bookingId: id,
      from: from,
      to: to,
      pickupIso: DateTime.now().toUtc().toIso8601String(),
      status: 'manual',
      currency: 'EUR',
    );

    await _startTrip(b);
  }

  Widget _buildBrandBar(bool tripActive) {
    // Robust top bar: larger logo + stronger presence.
    // Pulse only when a trip is active (cockpit mode).
    final pulse = tripActive ? (0.70 + 0.30 * _activePulse.value) : 0.0;

    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: kFluxidiPanel.withOpacity(0.88),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
                boxShadow: [
                  BoxShadow(
                    color: kFluxidiYellowSoft.withOpacity(
                      tripActive ? 0.55 * pulse : 0.20,
                    ),
                    blurRadius: tripActive ? (28 * pulse) : 18,
                    spreadRadius: tripActive ? (2 * pulse) : 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  _GlowIconButton(
                    icon: Icons.menu,
                    tooltip: 'Menu',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  const SizedBox(width: 10),
                  // Pulsing logo capsule (only on active trip)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.black.withOpacity(0.18),
                      border: Border.all(
                        color: const Color(0xFFFFD36A).withOpacity(
                          tripActive ? (0.30 + 0.25 * pulse) : 0.18,
                        ),
                      ),
                      boxShadow: tripActive
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0x66F5C400,
                                ).withOpacity(0.55 * pulse),
                                blurRadius: 26 * pulse,
                                spreadRadius: 2 * pulse,
                              ),
                            ]
                          : const [],
                    ),
                    child: Transform.scale(
                      scale: tripActive ? (1.00 + 0.05 * pulse) : 1.0,
                      child: _tenantLogo(
                        height: 40,
                        fallback: Text(
                          kCompanyName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tripActive ? 'Rit actief' : 'Driver console',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: tripActive
                          ? const Color(0xFF4CD964)
                          : Colors.white38,
                      shape: BoxShape.circle,
                      boxShadow: tripActive
                          ? [
                              BoxShadow(
                                color: const Color(0x554CD964).withOpacity(0.7),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// ===============================
  /// Fluxidi Cockpit UI (Design v1)
  /// ===============================

  /// Top status strip: branding + single dot (no extra text)
  Widget _buildStatusStrip(int state) {
    final bool active = state != 0;
    final media = MediaQuery.of(context);
    final bool compactNavHeader =
        media.orientation == Orientation.portrait &&
        _cameraMode == _CameraMode.follow;
    final dotColor = (state == 2)
        ? Colors.greenAccent
        : (state == 1)
        ? Colors.amberAccent
        : Colors.redAccent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: compactNavHeader ? 118 : 140,
          padding: EdgeInsets.symmetric(horizontal: compactNavHeader ? 10 : 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(compactNavHeader ? 0.30 : 0.22),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Row(
            children: [
              // Hamburger (everyone understands this)
              IconButton(
                tooltip: 'Menu',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: Icon(
                  Icons.menu_rounded,
                  color: Colors.white.withOpacity(0.88),
                  size: compactNavHeader ? 28 : 32,
                ),
              ),

              // Center logo (bigger, cockpit-style)
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _activePulseCtrl,
                    builder: (_, __) {
                      final pulse = active
                          ? (0.98 + 0.04 * _activePulse.value)
                          : 1.0;
                      return Transform.scale(
                        scale: compactNavHeader
                            ? (pulse * 1.06)
                            : (pulse * 1.18),
                        child: ClipRect(
                          child: SizedBox(
                            width: compactNavHeader ? 132 : 164,
                            height: compactNavHeader ? 46 : 58,
                            child: Center(
                              child: _tenantLogo(
                                height: compactNavHeader ? 38 : 50,
                                fit: BoxFit.contain,
                                fallback: const Icon(
                                  Icons.local_taxi,
                                  size: 32,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Single status dot (pulses only when active)
              AnimatedBuilder(
                animation: _activePulseCtrl,
                builder: (_, __) {
                  final pulse = active
                      ? (0.75 + 0.25 * _activePulse.value)
                      : 1.0;
                  return Transform.scale(
                    scale: compactNavHeader ? (pulse * 1.2) : (pulse * 1.6),
                    child: Container(
                      width: compactNavHeader ? 11 : 14,
                      height: compactNavHeader ? 11 : 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor.withOpacity(active ? 1.0 : 0.9),
                        boxShadow: [
                          BoxShadow(
                            color: dotColor.withOpacity(active ? 0.55 : 0.35),
                            blurRadius: active ? 18 : 10,
                            spreadRadius: active ? 2 : 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              SizedBox(width: compactNavHeader ? 6 : 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom glass HUD (map remains primary)
  Widget _buildCockpitHud({required bool liveActive}) {
    final b = _activeBooking;
    final from = (b?.from ?? '').trim();
    final to = (b?.to ?? '').trim();

    final routeText = [
      if (from.isNotEmpty) 'A: $from',
      if (to.isNotEmpty) 'B: $to',
    ].join('  ->  ');

    // Fallback if destination is missing
    final hasB = to.isNotEmpty;
    final routeTextSafe = hasB
        ? routeText
        : (routeText.isNotEmpty ? (routeText + '  ->  B: —') : 'B: —');

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.18),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Route ticker (only route, no labels/icons beyond A/B)
                if (routeText.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      color: Colors.white.withOpacity(0.06),
                      child: Center(
                        child: RouteMarquee(
                          key: const ValueKey('route_marquee'),
                          text: routeTextSafe,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            letterSpacing: 0.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Price orb + mode (fixed/live) — minimal, cockpit-style
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 18,
                              spreadRadius: 1,
                              color:
                                  (liveActive
                                          ? Colors.greenAccent
                                          : Colors.amberAccent)
                                      .withOpacity(0.12),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            liveActive ? '●' : '◐',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: liveActive
                                  ? Colors.greenAccent
                                  : Colors.amberAccent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                // Primary action
                Center(
                  child: SizedBox(
                    width: 220,
                    height: 56,
                    child: FilledButton(
                      style:
                          FilledButton.styleFrom(
                            backgroundColor: liveActive
                                ? Colors.redAccent.withOpacity(0.95)
                                : const Color(0xFF1B7F3A),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ).copyWith(
                            side: MaterialStateProperty.all(
                              BorderSide(
                                color: liveActive
                                    ? Colors.redAccent.withOpacity(0.95)
                                    : kFluxidiYellow.withOpacity(0.95),
                                width: 1.2,
                              ),
                            ),
                            overlayColor: MaterialStateProperty.all(
                              kFluxidiYellowSoft,
                            ),
                          ),
                      onPressed: () async {
                        if (liveActive) {
                          await _stopTripSafely();
                        } else {
                          final b = _activeBooking;
                          if (b == null) return;
                          await _startTrip(b);
                        }
                      },
                      child: Text(
                        liveActive ? 'STOP' : 'START',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dial({
    required String label,
    required String value,
    required bool big,
  }) {
    final size = big ? 92.0 : 78.0;
    final valueStyle = TextStyle(
      color: Colors.white,
      fontSize: big ? 26 : 18,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
    );

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.06),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, textAlign: TextAlign.center, style: valueStyle),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Active trip elapsed time
  Duration get _activeElapsed {
    final started = _trackingStartedAt;
    if (started == null) return Duration.zero;
    final now = DateTime.now();
    final d = now.difference(started);
    if (d.isNegative) return Duration.zero;
    return d;
  }

  String get _etaString {
    // ETA as countdown (remaining time), not clock-time.
    final totalSec = _routeDurationSec;
    if (totalSec == null || totalSec <= 0) return '—';

    final elapsed = _activeElapsed.inSeconds;
    final remaining = math.max(0, totalSec - elapsed);

    if (remaining < 60) return '<1 min';

    final minutes = (remaining / 60).ceil();
    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  Future<void> _stopTripSafely() async {
    // Keep existing stop logic if present
    await _stopTrip();
  }

  String _formatHms(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildBootSplashOverlay() {
    final pulse = _splashPulse.value;

    // Premium boot overlay: subtle golden aura + animated ring + logo shimmer.
    return IgnorePointer(
      ignoring: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        opacity: _showBootSplash ? 1 : 0,
        child: Container(
          color: const Color(0xFF070709),
          child: Stack(
            children: [
              // Background aura
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.25),
                      radius: 0.95,
                      colors: [
                        const Color(
                          0x33FFD36A,
                        ).withOpacity(0.35 + 0.15 * pulse),
                        const Color(0x00070709),
                      ],
                    ),
                  ),
                ),
              ),

              // Center brand
              Center(
                child: AnimatedBuilder(
                  animation: _splashAnimCtrl,
                  builder: (context, _) {
                    final p = _splashPulse.value;
                    final ringAlpha = (0.22 + 0.18 * p).clamp(0.0, 1.0);
                    final glowAlpha = (0.45 + 0.30 * p).clamp(0.0, 1.0);
                    final scale = 0.985 + 0.025 * p;

                    return Transform.scale(
                      scale: scale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 280,
                            height: 280,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer animated ring
                                Container(
                                  width: 268,
                                  height: 268,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Color.fromRGBO(
                                        255,
                                        211,
                                        106,
                                        ringAlpha,
                                      ),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color.fromRGBO(
                                          255,
                                          211,
                                          106,
                                          glowAlpha,
                                        ),
                                        blurRadius: 28 + 18 * p,
                                        spreadRadius: 2 + 2 * p,
                                      ),
                                    ],
                                  ),
                                ),

                                // Inner soft ring
                                Container(
                                  width: 214,
                                  height: 214,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Color.fromRGBO(
                                        255,
                                        211,
                                        106,
                                        (ringAlpha * 0.55).clamp(0.0, 1.0),
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                ),

                                // Logo + shimmer mask
                                ShaderMask(
                                  shaderCallback: (rect) {
                                    // Shimmer sweeps horizontally across the logo
                                    final t = _splashAnimCtrl.value; // 0..1
                                    final start = -0.6 + 1.6 * t;
                                    return LinearGradient(
                                      begin: Alignment(start, 0),
                                      end: Alignment(start + 0.8, 0),
                                      colors: const [
                                        Color(0x66FFFFFF),
                                        Color(0xFFFFFFFF),
                                        Color(0x66FFFFFF),
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                    ).createShader(rect);
                                  },
                                  blendMode: BlendMode.srcATop,
                                  child: SizedBox(
                                    width: 210,
                                    height: 210,
                                    child: _tenantLogo(
                                      height: 210,
                                      fallback: const Text(
                                        'FLUXIDI',
                                        style: TextStyle(
                                          color: Color(0xFFFFD36A),
                                          fontSize: 32,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            kCompanyName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Driver • Live Tracking',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.78),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Minimal loading hint
                          SizedBox(
                            width: 120,
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: const Color(0x22FFFFFF),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color.fromRGBO(
                                  255,
                                  211,
                                  106,
                                  (0.75 + 0.20 * p).clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _ghostButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: kFluxidiYellow.withOpacity(0.85), width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ).copyWith(overlayColor: MaterialStateProperty.all(kFluxidiYellowSoft));
  }

  ButtonStyle _startButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: Colors.black.withOpacity(0.55),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ).copyWith(
      side: MaterialStateProperty.all(
        BorderSide(color: kFluxidiYellow.withOpacity(0.95), width: 1.2),
      ),
      shadowColor: MaterialStateProperty.all(kFluxidiYellowSoft),
      elevation: MaterialStateProperty.all(0),
      overlayColor: MaterialStateProperty.all(kFluxidiYellowSoft),
    );
  }

  String _rideStatusLabel(String rawStatus) {
    final s = rawStatus.trim().toUpperCase();
    if (s.isEmpty || s == 'PENDING') return kRideStatusPendingLabel;
    if (s == 'COMPLETED') return kRideActionCompletedLabel;
    if (s == 'CANCELLED') return kRideActionCancelledLabel;
    return rawStatus.trim();
  }

  // -------------------------------
  // UI helpers for stats
  // -------------------------------

  int? _remainingSec() {
    final remainingKm = (_routeKm != null)
        ? (_routeKm! - _kmDriven).clamp(0.0, 999999.0)
        : null;
    if (_routeDurationSec == null ||
        _routeKm == null ||
        _routeKm! <= 0 ||
        remainingKm == null)
      return null;
    final ratio = (remainingKm / _routeKm!).clamp(0.0, 1.0);
    return (_routeDurationSec! * ratio).round();
  }

  String _fmtDur(int? sec) {
    if (sec == null) return '—';
    final m = (sec / 60).round();
    if (m < 60) return '$m min';
    final h = (m / 60).floor();
    final mm = m % 60;
    return '${h}u ${mm}m';
  }

  String _fmtRemainingKm() {
    final remainingKm = (_routeKm != null)
        ? (_routeKm! - _kmDriven).clamp(0.0, 999999.0)
        : null;
    if (remainingKm == null) return '—';
    return remainingKm.toStringAsFixed(1);
  }

  String _fmtPrice() {
    final b = _activeBooking;
    final amount = b == null ? null : _driverDisplayPriceForBooking(b);
    if (amount == null) return '—';
    return amount.toStringAsFixed(2);
  }

  String _fmtMoney(num amount, String currency) {
    // Keep it simple & predictable (no locale surprises)
    final value = amount.toDouble().toStringAsFixed(2);
    final cur = currency.toUpperCase();
    if (cur == 'EUR' || cur == 'EURO' || cur == '€') return '€ $value';
    if (cur.length <= 3) return '$cur $value';
    return '$value';
  }

  BookingItem? _nextVisibleBookingForDashboard() {
    final visible = _myAssignedVisibleBookings;
    if (visible.isEmpty) return null;
    final now = DateTime.now();
    final upcoming = visible
        .where((b) {
          final raw = (b.pickupIso ?? '').trim();
          if (raw.isEmpty) return true;
          final dt = DateTime.tryParse(raw);
          if (dt == null) return true;
          return !dt.toLocal().isBefore(
            now.subtract(const Duration(minutes: 5)),
          );
        })
        .toList(growable: false);
    final base = upcoming.isNotEmpty ? upcoming : visible;
    final sorted = [...base]
      ..sort((a, b) {
        DateTime normalize(BookingItem item) {
          final raw = (item.pickupIso ?? '').trim();
          final parsed = DateTime.tryParse(raw);
          return parsed?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(1 << 62);
        }

        return normalize(a).compareTo(normalize(b));
      });
    return sorted.first;
  }

  String _dashboardDriverName() {
    final profile = _dashboardActiveDriverProfile();
    final profileName = profile?.fullName.trim() ?? '';
    if (profileName.isNotEmpty) return profileName;
    final profileEmployee = profile?.employeeNumber.trim() ?? '';
    if (profileEmployee.isNotEmpty) return profileEmployee;
    final session = activeDriverSessionNotifier.value;
    final fullName = session?.fullName.trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    final employee = session?.employeeNumber.trim() ?? '';
    if (employee.isNotEmpty) return employee;
    return 'chauffeur';
  }

  DriverProfile? _dashboardActiveDriverProfile() {
    final session = activeDriverSessionNotifier.value;
    final previewDriverId = (_businessPreviewDriverId ?? '').trim();
    final sessionDriverId = session?.driverId.trim() ?? '';
    final preferredDriverId =
        widget.openedFromBusinessHome && previewDriverId.isNotEmpty
        ? previewDriverId
        : sessionDriverId;
    if (preferredDriverId.isNotEmpty) {
      for (final driver in driversNotifier.value) {
        if (driver.id.trim() == preferredDriverId) return driver;
      }
    }
    if (sessionDriverId.isEmpty) return null;
    for (final driver in driversNotifier.value) {
      if (driver.id.trim() == sessionDriverId) return driver;
    }
    return null;
  }

  String? _resolveFleetVehicleIdForDriver(String driverId) {
    final activeCompany = resolvedCompanyId.trim().isNotEmpty
        ? resolvedCompanyId.trim()
        : kOutboundTenantId.trim();
    return resolveFleetVehicleIdForDriver(
      driverId,
      companyId: activeCompany.isNotEmpty ? activeCompany : null,
    );
  }

  String _effectiveActiveDriverIdForRideScope() {
    if (widget.openedFromBusinessHome) {
      final preview = (_businessPreviewDriverId ?? '').trim();
      if (preview.isNotEmpty) return preview;
    }
    final sessionDriverId =
        activeDriverSessionNotifier.value?.driverId.trim() ?? '';
    if (sessionDriverId.isNotEmpty) return sessionDriverId;
    return resolvedDriverTrackingId.trim();
  }

  String _effectiveActiveVehicleIdForRideScope() {
    final driverId = _effectiveActiveDriverIdForRideScope();
    final fleetVehicle = driverId.isNotEmpty
        ? _resolveFleetVehicleIdForDriver(driverId)
        : null;
    if ((fleetVehicle ?? '').trim().isNotEmpty) return fleetVehicle!.trim();
    return activeDriverSessionNotifier.value?.assignedVehicleId?.trim() ?? '';
  }

  void _syncDriverRideScopeContext({required String reason}) {
    if (!_isInDriverUiContext) {
      driverRideScopeActiveDriverIdOverride.value = '';
      driverRideScopeActiveVehicleIdOverride.value = '';
      return;
    }
    final effectiveDriverId = _effectiveActiveDriverIdForRideScope();
    final effectiveVehicleId = _effectiveActiveVehicleIdForRideScope();
    driverRideScopeActiveDriverIdOverride.value = effectiveDriverId;
    driverRideScopeActiveVehicleIdOverride.value = effectiveVehicleId;
    final previewDriverId = (_businessPreviewDriverId ?? '').trim();
    final sessionDriverId =
        activeDriverSessionNotifier.value?.driverId.trim() ?? '';
    final source = widget.openedFromBusinessHome
        ? 'business_preview'
        : (previewDriverId.isNotEmpty ? 'business_home' : 'standalone_driver');
    debugPrint(
      '[DRIVER_VIEW_ORIGIN][CURRENT] source=$source reason=$reason preview=${_maskBridgeDriverIdGlobal(previewDriverId)} session=${_maskBridgeDriverIdGlobal(sessionDriverId)} effective=${_maskBridgeDriverIdGlobal(effectiveDriverId)} vehicle=${_safeRefPreview(effectiveVehicleId)}',
    );
    debugPrint(
      '[DRIVER_RIDES][EFFECTIVE_DRIVER] source=$source reason=$reason driver=${_maskBridgeDriverIdGlobal(effectiveDriverId)} vehicle=${_safeRefPreview(effectiveVehicleId)} session=${_maskBridgeDriverIdGlobal(sessionDriverId)} preview=${_maskBridgeDriverIdGlobal(previewDriverId)}',
    );
  }

  void _logRidesHubVisibleCounts({required String source}) {
    final myRides = _myAssignedVisibleBookings;
    final available = _availableUnassignedVisibleBookings;
    final myFirst = myRides.isNotEmpty
        ? _safeRefPreview(myRides.first.bookingId)
        : '-';
    final availableFirst = available.isNotEmpty
        ? _safeRefPreview(available.first.bookingId)
        : '-';
    debugPrint(
      '[DRIVER_RIDES][MY_RIDES_VISIBLE_COUNT] count=${myRides.length} source=$source first=$myFirst',
    );
    debugPrint(
      '[DRIVER_RIDES][AVAILABLE_VISIBLE_COUNT] count=${available.length} source=$source first=$availableFirst',
    );
  }

  String _effectiveCurrentDriverIdForBusinessPreview() {
    final previewDriverId = (_businessPreviewDriverId ?? '').trim();
    if (widget.openedFromBusinessHome && previewDriverId.isNotEmpty) {
      return previewDriverId;
    }
    return activeDriverSessionNotifier.value?.driverId.trim() ?? '';
  }

  void _logCurrentDriverOrigin({required String reason}) {
    _syncDriverRideScopeContext(reason: reason);
  }

  // G3-L: when the user opens the My-rides segment, log the visible count and
  // — only when we are in the business-preview entry path or the cached list
  // is stale — force one fresh /driver/bookings fetch. The standalone driver
  // app already gets a fresh fetch from its own polling/login flow, so it
  // does not need this extra force; we cooldown-gate so chip-tap-bouncing
  // cannot spam the backend.
  void _maybeForceRefreshOnMyRidesOpen({required String source}) {
    if (!mounted) return;
    _logRidesHubVisibleCounts(source: source);
    final now = DateTime.now();
    final fromBusinessPreview = widget.openedFromBusinessHome;
    final lastRefresh = _lastBookingsRefreshAt;
    final stale =
        lastRefresh == null ||
        now.difference(lastRefresh) >= _bookingsMinRefreshIntervalSafeLive;
    if (!fromBusinessPreview && !stale) return;
    if (_lastBusinessPreviewMyRidesRefreshAt != null &&
        now.difference(_lastBusinessPreviewMyRidesRefreshAt!) <
            _businessPreviewMyRidesRefreshCooldown) {
      return;
    }
    _lastBusinessPreviewMyRidesRefreshAt = now;
    if (fromBusinessPreview) {
      debugPrint(
        '[DRIVER_VIEW_ORIGIN][BUSINESS_PREVIEW_REFRESH] reason=my_rides_segment driver=${_maskBridgeDriverIdGlobal(_effectiveCurrentDriverIdForBusinessPreview())}',
      );
    }
    unawaited(_refreshBookings(force: true, trigger: 'my_rides_segment'));
  }

  String? _dashboardAvatarPhotoPath() {
    final candidate =
        _dashboardActiveDriverProfile()?.profilePhotoPath?.trim() ?? '';
    if (candidate.isEmpty) return null;
    if (kIsWeb) return null;
    try {
      return File(candidate).existsSync() ? candidate : null;
    } catch (_) {
      return null;
    }
  }

  String? _resolveDashboardDriverPhotoUrl(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    final resolved = resolvePublicHttpsMediaUrl(text);
    if (resolved.isNotEmpty) return resolved;
    final lower = text.toLowerCase();
    if (lower.startsWith('https://') || lower.startsWith('http://'))
      return text;
    return null;
  }

  String? _dashboardAvatarNetworkUrl() {
    bool isPreferredFluxidiMediaUrl(String value) {
      final lower = value.trim().toLowerCase();
      return lower.contains('/public/media/') ||
          lower.contains('public-media/') ||
          lower.contains('/public-media/');
    }

    final profile = _dashboardActiveDriverProfile();
    final session = activeDriverSessionNotifier.value;
    final effectiveDriverId = _effectiveActiveDriverIdForRideScope();
    final sessionDriverId = session?.driverId.trim() ?? '';
    final backendPhoto = (profile?.publicPortraitUrl ?? '').trim();
    final sessionPhoto = (session?.driverPhotoUrl ?? '').trim();
    if (sessionPhoto.isNotEmpty &&
        sessionDriverId.isNotEmpty &&
        effectiveDriverId.isNotEmpty &&
        sessionDriverId != effectiveDriverId) {
      debugPrint(
        '[DRIVER_PHOTO_CANONICAL][MISMATCH_BLOCK] requested_driver=${_maskBridgeDriverIdGlobal(effectiveDriverId)} cached_driver=${_maskBridgeDriverIdGlobal(sessionDriverId)}',
      );
    }
    final sessionPhotoForEffective =
        sessionDriverId.isNotEmpty &&
            effectiveDriverId.isNotEmpty &&
            sessionDriverId == effectiveDriverId
        ? sessionPhoto
        : '';
    final resolvedSessionPhoto = _resolveDashboardDriverPhotoUrl(
      sessionPhotoForEffective,
    );
    final resolvedBackendPhoto = _resolveDashboardDriverPhotoUrl(backendPhoto);
    final isBusinessPreview =
        widget.openedFromBusinessHome &&
        (session?.isCompanyAdminDriverViewSession ?? false);

    String source = 'fallback';
    String? selected;
    if (isBusinessPreview) {
      if (resolvedBackendPhoto != null &&
          (profile?.id.trim() ?? '') == effectiveDriverId) {
        selected = resolvedBackendPhoto;
        source = profile != null ? 'local' : 'backend';
      } else if (resolvedSessionPhoto != null) {
        selected = resolvedSessionPhoto;
        source = 'session';
      }
    } else {
      if (resolvedSessionPhoto != null) {
        selected = resolvedSessionPhoto;
        source = 'session';
      } else if (resolvedBackendPhoto != null) {
        selected = resolvedBackendPhoto;
        source = profile != null ? 'local' : 'backend';
      }
    }
    if (backendPhoto.isNotEmpty &&
        isPreferredFluxidiMediaUrl(backendPhoto) &&
        sessionPhoto.isNotEmpty &&
        !isPreferredFluxidiMediaUrl(sessionPhoto)) {
      debugPrint(
        '[DRIVER_PHOTO_CANONICAL][LEGACY_IGNORED] driver=${_shortDriverIdForDiag(profile?.id ?? session?.driverId ?? "")} reason=session_legacy_remote_overridden',
      );
    }
    // If we resolved a real photo for the effective driverId, remember it so
    // brief session-null windows during restore do not regress the avatar.
    final cacheDriverId = effectiveDriverId.isNotEmpty
        ? effectiveDriverId
        : sessionDriverId;
    if (selected != null && cacheDriverId.isNotEmpty) {
      _rememberLastKnownDriverPhoto(cacheDriverId, selected);
    }
    if (selected == null && !isBusinessPreview) {
      // Restore-in-progress / brief session-null window: prefer last known
      // photo for the SAME driverId. Never swap photos across drivers.
      final preserveDriverId = cacheDriverId;
      if (preserveDriverId.isNotEmpty) {
        final preserved = _readLastKnownDriverPhoto(preserveDriverId);
        if (preserved != null) {
          debugPrint(
            '[DRIVER_PHOTO_CANONICAL][PRESERVE] driver=${_shortDriverIdForDiag(preserveDriverId)} reason=session_restore_in_progress',
          );
          selected = preserved;
          source = 'preserved';
        }
      }
    }
    final photoState = selected == null ? 'missing' : 'present';
    debugPrint(
      '[DRIVER_PHOTO_CANONICAL][RESOLVE] driver=${_shortDriverIdForDiag(profile?.id ?? session?.driverId ?? "")} source=$source photo=$photoState reason=${isBusinessPreview ? 'business_preview' : 'standalone'}',
    );
    debugPrint(
      '[DRIVER_PHOTO_CANONICAL][SOURCE] driver=${_shortDriverIdForDiag(profile?.id ?? session?.driverId ?? "")} source=$source',
    );
    debugPrint(
      '[DRIVER_PHOTO_CANONICAL][DONE] driver=${_shortDriverIdForDiag(profile?.id ?? session?.driverId ?? "")} urlSource=$source',
    );
    return selected;
  }

  String _dashboardGreeting() {
    final name = _dashboardDriverName();
    if (name.toLowerCase() == 'chauffeur') {
      return _tr(
        nl: 'Welkom chauffeur',
        en: 'Welcome driver',
        fr: 'Bienvenue chauffeur',
        es: 'Bienvenido conductor',
      );
    }
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return _tr(
        nl: 'Goedemorgen, $name!',
        en: 'Good morning, $name!',
        fr: 'Bonjour, $name !',
        es: 'Buenos dias, $name!',
      );
    }
    if (hour < 18) {
      return _tr(
        nl: 'Goedemiddag, $name!',
        en: 'Good afternoon, $name!',
        fr: 'Bon apres-midi, $name !',
        es: 'Buenas tardes, $name!',
      );
    }
    return _tr(
      nl: 'Goedenavond, $name!',
      en: 'Good evening, $name!',
      fr: 'Bonsoir, $name !',
      es: 'Buenas noches, $name!',
    );
  }

  _DriverDashboardStatus _dashboardDriverStatus() {
    final activeRide = _liveRideActive || _isTracking;
    if (activeRide && _isWaiting) return _DriverDashboardStatus.waiting;
    if (activeRide) return _DriverDashboardStatus.busy;

    final hasNavLeg =
        _activeBooking != null ||
        (_cameraMode == _CameraMode.follow &&
            (_activeBooking != null ||
                (_directRideDestinationText ?? '').trim().isNotEmpty));
    if (hasNavLeg) return _DriverDashboardStatus.onTheWay;

    final operational = normalizeDriverAvailabilityState(
      _resolvedOperationalAvailabilityForDriver(
        profile: _dashboardActiveDriverProfile(),
      ),
      fallback: 'available',
    );
    if (operational == 'offline') return _DriverDashboardStatus.pause;
    if (operational == 'paused') return _DriverDashboardStatus.pause;
    return _DriverDashboardStatus.ready;
  }

  String _dashboardAvailabilityButtonAction({String? availabilityStatus}) {
    final normalized = normalizeDriverAvailabilityState(
      availabilityStatus ?? _resolvedOperationalAvailability,
      fallback: 'available',
    );
    switch (normalized) {
      case 'paused':
        return 'resume';
      case 'offline':
        return 'start_shift';
      default:
        return 'pause';
    }
  }

  String _dashboardAvailabilityActionLabel() {
    switch (_dashboardAvailabilityButtonAction()) {
      case 'resume':
        return _tr(
          nl: 'Hervatten',
          en: 'Resume',
          fr: 'Reprendre',
          es: 'Reanudar',
        );
      case 'start_shift':
        return _tr(
          nl: 'Dienst starten',
          en: 'Start shift',
          fr: 'Commencer le service',
          es: 'Iniciar turno',
        );
      default:
        return _tr(nl: 'Pauze', en: 'Pause', fr: 'Pause', es: 'Pausa');
    }
  }

  String _dashboardStatusLabel() {
    switch (_dashboardDriverStatus()) {
      case _DriverDashboardStatus.busy:
        return _tr(nl: 'Bezet', en: 'Busy', fr: 'Occupe', es: 'Ocupado');
      case _DriverDashboardStatus.waiting:
        return _tr(
          nl: 'Wachten',
          en: 'Waiting',
          fr: 'En attente',
          es: 'Esperando',
        );
      case _DriverDashboardStatus.onTheWay:
        return _tr(
          nl: 'Onderweg',
          en: 'On the way',
          fr: 'En route',
          es: 'En camino',
        );
      case _DriverDashboardStatus.pause:
        return _tr(nl: 'Pauze', en: 'Pause', fr: 'Pause', es: 'Pausa');
      case _DriverDashboardStatus.ready:
        return _tr(nl: 'Klaar', en: 'Ready', fr: 'Pret', es: 'Listo');
    }
  }

  String _dashboardNextRideTime(BookingItem? booking) {
    if (booking == null) return '—';
    final raw = (booking.pickupIso ?? '').trim();
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  bool _isCompletedTripStatusForDashboard(dynamic rawStatus) {
    final status = (rawStatus ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    return status == 'completed' ||
        status == 'stopped' ||
        status == 'finalized' ||
        status == 'finished' ||
        status == 'done' ||
        status == 'closed';
  }

  DateTime? _dashboardTripCompletionLocalDate(Map<String, dynamic> trip) {
    final candidates = <dynamic>[
      trip['stopped_at'],
      trip['stoppedAt'],
      trip['ended_at'],
      trip['endedAt'],
      trip['completed_at'],
      trip['completedAt'],
      trip['created_at'],
      trip['createdAt'],
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final parsed = DateTime.tryParse(text);
      if (parsed != null) return parsed.toLocal();
    }
    return null;
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _completedTodayCardValue() {
    if (_completedTodayLoading) return '—';
    return _completedTodayCount?.toString() ?? '—';
  }

  Future<void> _refreshCompletedTodayCount({required String reason}) async {
    if (!mounted) return;
    setState(() => _completedTodayLoading = true);

    try {
      final strictScope = _strictDriverHistoryScopeIdsWithSource();
      if (strictScope == null) {
        debugPrint(
          '[DRIVER_DASHBOARD][COMPLETED_TODAY][SKIP_SCOPE] reason=missing_tenant_company_scope source=$reason',
        );
        if (!mounted) return;
        setState(() {
          _completedTodayCount = null;
          _completedTodayLoading = false;
        });
        return;
      }
      final driverId = kDriverId.trim();
      if (driverId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _completedTodayCount = null;
          _completedTodayLoading = false;
        });
        return;
      }

      final uri = Uri.parse(
        '$kWorkerBaseUrl$kTripsHistoryPath'
        '?tenant_id=${Uri.encodeQueryComponent(strictScope.tenantId)}'
        '&company_id=${Uri.encodeQueryComponent(strictScope.companyId)}'
        '&tenantId=${Uri.encodeQueryComponent(strictScope.tenantId)}'
        '&companyId=${Uri.encodeQueryComponent(strictScope.companyId)}'
        '&driver_id=${Uri.encodeQueryComponent(driverId)}'
        '&limit=200',
      );
      final historyHeaders = await _tripsHistoryAuthHeaders(
        scopeSource: strictScope.source,
        driverId: driverId,
        fetchContext: 'completed_today',
      );
      final res = await http
          .get(uri, headers: historyHeaders)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception('history_http_${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception('history_invalid_payload');
      }

      final tripsRaw = decoded['trips'];
      final trips = tripsRaw is List
          ? tripsRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e))
          : const Iterable<Map<String, dynamic>>.empty();
      final today = DateTime.now();
      final seenTripIds = <String>{};
      var completedToday = 0;
      for (final trip in trips) {
        final tripId = (trip['trip_id'] ?? trip['tripId'] ?? '')
            .toString()
            .trim();
        if (tripId.isNotEmpty && !seenTripIds.add(tripId)) {
          continue;
        }
        if (!_isCompletedTripStatusForDashboard(trip['status'])) continue;
        final completionDate = _dashboardTripCompletionLocalDate(trip);
        if (completionDate == null) continue;
        if (_isSameLocalDay(completionDate, today)) {
          completedToday++;
        }
      }

      if (!mounted) return;
      setState(() {
        _completedTodayCount = completedToday;
        _completedTodayLoading = false;
      });
    } catch (e) {
      debugPrint(
        '[DRIVER_DASHBOARD][COMPLETED_TODAY][WARN] reason=$reason error=$e',
      );
      if (!mounted) return;
      setState(() {
        _completedTodayCount = null;
        _completedTodayLoading = false;
      });
    }
  }

  void _goBackToStartFromDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleEntryPage()),
      (route) => false,
    );
  }

  /// Handle the standalone "Switch driver" action from the More menu.
  /// Safe by design:
  ///   - blocked in business preview / company-admin chauffeurweergave
  ///   - blocked while a live ride is active
  ///   - clears ONLY the standalone driver session + standalone scope pointer
  ///     (no company / business / customer session is touched)
  ///   - navigates to [ChauffeurLoginPage] for a fresh login.
  Future<void> _handleStandaloneSwitchDriverRequest() async {
    if (!mounted) return;
    final session = activeDriverSessionNotifier.value;
    final maskedDriver = _shortDriverIdForDiag(session?.driverId ?? '');
    debugPrint(
      '[DRIVER_SESSION][SWITCH_REQUEST] driver=$maskedDriver business_preview=${widget.openedFromBusinessHome} live_ride=$_liveRideActive',
    );

    if (widget.openedFromBusinessHome ||
        (session?.isCompanyAdminDriverViewSession ?? false)) {
      debugPrint(
        '[DRIVER_SESSION][SWITCH_BLOCKED] reason=business_preview driver=$maskedDriver',
      );
      _toast(
        _tr(
          nl: 'Wissel chauffeur is alleen beschikbaar in de chauffeurs-app, niet in de bedrijfsweergave.',
          en: 'Switch driver is only available in the standalone driver app, not in the business preview.',
          fr: 'Changer de chauffeur n\'est disponible que dans l\'application chauffeur, pas dans l\'apercu entreprise.',
          es: 'Cambiar conductor solo esta disponible en la aplicacion del conductor, no en la vista previa de empresa.',
        ),
      );
      return;
    }

    if (_liveRideActive) {
      debugPrint(
        '[DRIVER_SESSION][SWITCH_BLOCKED] reason=active_ride driver=$maskedDriver',
      );
      _toast(
        _tr(
          nl: 'Beeindig of annuleer eerst de actieve rit voordat je van chauffeur wisselt.',
          en: 'Finish or cancel the active ride before switching drivers.',
          fr: 'Terminez ou annulez la course en cours avant de changer de chauffeur.',
          es: 'Termina o cancela la carrera activa antes de cambiar de conductor.',
        ),
      );
      return;
    }

    if (session == null) {
      debugPrint(
        '[DRIVER_SESSION][SWITCH_BLOCKED] reason=missing_session driver=$maskedDriver',
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _tr(
            nl: 'Wissel chauffeur?',
            en: 'Switch driver?',
            fr: 'Changer de chauffeur ?',
            es: '\u00bfCambiar conductor?',
          ),
        ),
        content: Text(
          _tr(
            nl:
                'De huidige chauffeurs-sessie wordt afgemeld op dit toestel. '
                'Bedrijfs- en klantgegevens blijven bewaard.',
            en:
                'The current driver session will be signed out on this device. '
                'Company and customer data are kept intact.',
            fr:
                'La session chauffeur actuelle sera deconnectee sur cet appareil. '
                'Les donnees entreprise et client restent intactes.',
            es:
                'La sesion del conductor actual se cerrara en este dispositivo. '
                'Los datos de empresa y cliente se mantienen intactos.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _tr(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.swap_horiz),
            label: Text(
              _tr(
                nl: 'Wissel chauffeur',
                en: 'Switch driver',
                fr: 'Changer de chauffeur',
                es: 'Cambiar conductor',
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    debugPrint('[DRIVER_SESSION][SWITCH_CONFIRMED] driver=$maskedDriver');
    debugPrint(
      '[DRIVER_SESSION][SWITCH_CLEAR] scope=standalone_only driver=$maskedDriver',
    );
    // clear() removes the scoped session file + standalone scope pointer +
    // in-memory cache + nulls activeDriverSessionNotifier. It does NOT touch
    // CompanySessionStore / CustomerSessionStore / business preview state.
    await DriverSessionStore.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const ChauffeurLoginPage()),
      (route) => false,
    );
  }

  bool _hasCompanyAdminDriverBridgeContext() {
    return CompanySessionStore.instance.hasValidCompanyContext &&
        _isCompanyAdminDriverViewSession(activeDriverSessionNotifier.value);
  }

  bool _canSwitchCompanyDriversFromDashboard() {
    if (_hasCompanyAdminDriverBridgeContext()) return true;
    if (!widget.openedFromBusinessHome) return false;
    return CompanySessionStore.instance.hasValidCompanyContext;
  }

  ({String tenantId, String companyId})? _activeBusinessPreviewScope() {
    if (!CompanySessionStore.instance.hasValidCompanyContext) return null;
    final profileCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    final sessionCompanyId =
        (activeCompanySessionNotifier.value?.companyId ?? '').trim();
    if (profileCompanyId.isNotEmpty &&
        sessionCompanyId.isNotEmpty &&
        profileCompanyId != sessionCompanyId) {
      return null;
    }
    final resolvedCompanyId = profileCompanyId.isNotEmpty
        ? profileCompanyId
        : sessionCompanyId;
    if (resolvedCompanyId.isEmpty) return null;
    return (tenantId: resolvedCompanyId, companyId: resolvedCompanyId);
  }

  bool _businessPreviewSessionIdentityMatches({
    required ActiveDriverSession session,
    required String driverId,
    required String tenantId,
    required String companyId,
  }) {
    if (driverId.trim().isEmpty ||
        tenantId.trim().isEmpty ||
        companyId.trim().isEmpty) {
      return false;
    }
    return session.driverId.trim() == driverId.trim() &&
        (session.tenantId ?? '').trim() == tenantId.trim() &&
        (session.companyId ?? '').trim() == companyId.trim();
  }

  bool _isBusinessPreviewDriverSessionTokenUsable(ActiveDriverSession session) {
    final token = (session.driverSessionToken ?? '').trim();
    if (token.isEmpty) return false;
    final expiresRaw = (session.driverSessionExpiresAtUtc ?? '').trim();
    if (expiresRaw.isEmpty) return true;
    final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc();
    if (expiresAt == null) return true;
    return expiresAt.isAfter(DateTime.now().toUtc());
  }

  ({String? token, String? tokenExpiryUtc, String source})
  _resolveBusinessPreviewSessionToken({
    required DriverProfile driver,
    required String resolvedTenantId,
    required String resolvedCompanyId,
    ActiveDriverSession? previous,
    ActiveDriverSession? persisted,
  }) {
    // Business preview never borrows standalone chauffeur session tokens.
    debugPrint(
      '[DRIVER_SESSION][SKIP_STANDALONE_VALIDATION] reason=business_preview action=skip_token_reuse',
    );
    return (token: null, tokenExpiryUtc: null, source: 'none');
  }

  Future<ActiveDriverSession?> _loadPersistedDriverSessionForPreview({
    required String reason,
  }) async {
    if (_isBusinessPreviewMode) {
      debugPrint(
        '[DRIVER_SESSION][SKIP_STANDALONE_VALIDATION] reason=business_preview action=skip_persisted_standalone_load trigger=$reason',
      );
      return null;
    }
    try {
      final persisted = await DriverSessionStore.instance.load();
      if (persisted == null) return null;
      if (persisted.isCompanyAdminDriverViewSession) return null;
      if (!persisted.isStandaloneLoginSession) return null;
      return persisted;
    } catch (_) {
      debugPrint(
        '[DRIVER_PREVIEW][TOKEN] reason=$reason token_present=false source=persisted_load error=load_failed',
      );
      return null;
    }
  }

  ActiveDriverSession _buildBusinessPreviewDriverSession({
    required DriverProfile driver,
    required ActiveDriverSession? previous,
    ActiveDriverSession? persisted,
    required String reason,
    String? photoOverride,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final profileCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    final sessionCompanyId =
        (activeCompanySessionNotifier.value?.companyId ?? '').trim();
    final fallbackCompanyId = (driver.companyId ?? '').trim();
    final resolvedCompanyId = profileCompanyId.isNotEmpty
        ? profileCompanyId
        : (sessionCompanyId.isNotEmpty ? sessionCompanyId : fallbackCompanyId);
    final resolvedTenantId = resolvedCompanyId;
    final resolvedCompanyCode =
        (activeCompanySessionNotifier.value?.companyCode ?? '').trim();
    final fleetVehicleId = _resolveFleetVehicleIdForDriver(driver.id.trim());
    final requestedDriverId = driver.id.trim();
    final previousDriverId = previous?.driverId.trim() ?? '';
    final portraitUrl = () {
      final profilePhoto = _canonicalDriverPortraitUrlGlobal(driver);
      if (profilePhoto.isNotEmpty) return profilePhoto;
      final override = (photoOverride ?? '').trim();
      if (override.isNotEmpty) return override;
      if (previousDriverId.isNotEmpty &&
          previousDriverId != requestedDriverId) {
        debugPrint(
          '[DRIVER_PHOTO_CANONICAL][MISMATCH_BLOCK] requested_driver=${_maskBridgeDriverIdGlobal(requestedDriverId)} cached_driver=${_maskBridgeDriverIdGlobal(previousDriverId)}',
        );
        return '';
      }
      return (previous?.driverPhotoUrl ?? '').trim();
    }();
    if (previousDriverId.isNotEmpty && previousDriverId != requestedDriverId) {
      debugPrint(
        '[DRIVER_SESSION][BUSINESS_PREVIEW_PHOTO_REFRESH] old_driver=${_maskBridgeDriverIdGlobal(previousDriverId)} new_driver=${_maskBridgeDriverIdGlobal(requestedDriverId)} photo=${portraitUrl.isEmpty ? 'missing' : 'present'}',
      );
    }
    if (portraitUrl.isNotEmpty) {
      debugPrint(
        '[DRIVER_SESSION][BUSINESS_PREVIEW_PHOTO] driver=${_maskBridgeDriverIdGlobal(driver.id)} photo=${portraitUrl.length <= 12 ? 'present' : '${portraitUrl.substring(0, 6)}…${portraitUrl.substring(portraitUrl.length - 4)}'}',
      );
    }
    final resolvedToken = _resolveBusinessPreviewSessionToken(
      driver: driver,
      resolvedTenantId: resolvedTenantId,
      resolvedCompanyId: resolvedCompanyId,
      previous: previous,
      persisted: persisted,
    );
    final tokenPresent = (resolvedToken.token ?? '').trim().isNotEmpty;
    debugPrint(
      '[DRIVER_PREVIEW][TOKEN] reason=$reason token_present=$tokenPresent source=${resolvedToken.source}',
    );
    return ActiveDriverSession(
      driverId: driver.id.trim(),
      employeeNumber: driver.employeeNumber.trim(),
      fullName: driver.fullName,
      phone: driver.phone,
      loggedInAt: previous?.loggedInAt ?? now,
      updatedAt: now,
      tenantId: resolvedTenantId.isEmpty ? null : resolvedTenantId,
      companyId: resolvedCompanyId.isEmpty ? null : resolvedCompanyId,
      companyCode: resolvedCompanyCode.isEmpty ? null : resolvedCompanyCode,
      assignedVehicleId: fleetVehicleId,
      driverPhotoUrl: portraitUrl.isEmpty ? null : portraitUrl,
      driverSessionToken: resolvedToken.token,
      driverSessionExpiresAtUtc: resolvedToken.tokenExpiryUtc,
      linkMethod: kCompanyAdminDriverViewLinkMethod,
    );
  }

  Future<ActiveDriverSession> _hydrateBusinessPreviewDriverSession({
    required DriverProfile driver,
    required String reason,
    String? photoOverride,
  }) async {
    final previous = activeDriverSessionNotifier.value;
    final notifierTokenPresent = (previous?.driverSessionToken ?? '')
        .trim()
        .isNotEmpty;
    debugPrint(
      '[DRIVER_PREVIEW][TOKEN] reason=$reason token_present=$notifierTokenPresent source=notifier',
    );
    ActiveDriverSession? persisted;
    if (!notifierTokenPresent) {
      debugPrint(
        '[DRIVER_PREVIEW][TOKEN] reason=$reason token_present=false source=notifier attempting=persisted_load',
      );
      persisted = await _loadPersistedDriverSessionForPreview(reason: reason);
      final persistedTokenPresent = (persisted?.driverSessionToken ?? '')
          .trim()
          .isNotEmpty;
      debugPrint(
        '[DRIVER_PREVIEW][TOKEN] reason=$reason token_present=$persistedTokenPresent source=persisted_load',
      );
    }
    final built = _buildBusinessPreviewDriverSession(
      driver: driver,
      previous: previous,
      persisted: persisted,
      reason: reason,
      photoOverride: photoOverride,
    );
    DriverSessionStore.instance.setBusinessDriverViewSessionInMemory(built);
    return built;
  }

  Future<void> _restoreBusinessPreviewDriverSelectionOnOpen() async {
    if (!widget.openedFromBusinessHome) return;
    final scope = _activeBusinessPreviewScope();
    if (scope == null) {
      debugPrint(
        '[DRIVER_VIEW_ORIGIN][PREVIEW_LOAD] source=business_home driver=missing reason=missing_scope',
      );
      return;
    }
    final savedPreview = await DriverSessionStore.instance
        .loadBusinessDriverPreview(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
    final resolvedPreview = _resolveBusinessDriverForPreviewGlobal(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
      savedPreview: savedPreview,
    );
    final selectedDriver = resolvedPreview.driver;
    if (selectedDriver == null) {
      _businessPreviewDriverId = null;
      if (savedPreview != null) {
        await DriverSessionStore.instance.clearBusinessPreviewDriverSelection(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
      }
      debugPrint(
        '[DRIVER_VIEW_ORIGIN][PREVIEW_LOAD] source=business_home driver=missing reason=${savedPreview == null ? 'no_saved_preview' : 'invalid_or_inactive'}',
      );
      _logCurrentDriverOrigin(reason: 'preview_load_empty');
      final adminCandidates =
          _resolveOperationalCockpitDriverBridgeCandidatesGlobal(
            companyId: scope.companyId,
            logCandidates: false,
          );
      if (adminCandidates.isNotEmpty) {
        final fallbackDriver = adminCandidates.first;
        _businessPreviewDriverId = fallbackDriver.id.trim();
        activeDriverSessionNotifier.value =
            await _hydrateBusinessPreviewDriverSession(
              driver: fallbackDriver,
              reason: 'preview_load_fallback_first',
            );
        await _saveBusinessDriverPreviewFromProfileGlobal(
          fallbackDriver,
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
        _syncDriverRideScopeContext(reason: 'preview_load_fallback_first');
      }
      if (!mounted) return;
      unawaited(_refreshBookings(force: true, trigger: 'init_boot'));
      return;
    }
    _businessPreviewDriverId = selectedDriver.id.trim();
    activeDriverSessionNotifier.value =
        await _hydrateBusinessPreviewDriverSession(
          driver: selectedDriver,
          reason: 'preview_load_applied',
          photoOverride:
              savedPreview != null &&
                  savedPreview.driverId.trim() == selectedDriver.id.trim()
              ? savedPreview.driverPhotoUrl
              : null,
        );
    if (resolvedPreview.reason == 'vehicle_assignment' ||
        resolvedPreview.reason == 'first_assigned_driver' ||
        resolvedPreview.reason == 'saved_preview' ||
        savedPreview == null ||
        savedPreview.driverId.trim() != selectedDriver.id.trim()) {
      await _saveBusinessDriverPreviewFromProfileGlobal(
        selectedDriver,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
    }
    _syncDriverRideScopeContext(reason: 'preview_load_applied');
    debugPrint(
      '[DRIVER_VIEW_ORIGIN][PREVIEW_LOAD] source=business_home driver=${_maskBridgeDriverIdGlobal(selectedDriver.id)} reason=${resolvedPreview.reason}',
    );
    _logCurrentDriverOrigin(reason: 'preview_load_applied');
    if (mounted) setState(() {});
    _reconcileDriverAvailability(
      source: 'local',
      reason: 'preview_load_applied',
      incomingStatus: normalizeDriverAvailabilityState(
        selectedDriver.availabilityStatus,
        fallback: 'available',
      ),
    );
    unawaited(
      _refreshDriverAvailabilityFromBackend(
        reason: 'preview_load_applied',
        force: true,
      ),
    );
    debugPrint(
      '[DRIVER_VIEW_ORIGIN][BUSINESS_PREVIEW_REFRESH] reason=preview_restore driver=${_maskBridgeDriverIdGlobal(selectedDriver.id)}',
    );
    unawaited(
      _refreshBookings(force: true, trigger: 'business_preview_restore'),
    );
  }

  void _goBackToBusinessPageFromDashboard() {
    setAppRole(AppRole.companyAdmin);
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const BusinessHomePage()),
      (route) => false,
    );
  }

  Future<void> _refreshDriverBridgeCandidatesIfNeeded() async {
    final activeCompanyId = _firstBootstrapText(<dynamic>[
      companyProfileNotifier.value?.companyId,
      activeCompanySessionNotifier.value?.companyId,
    ]);
    if (activeCompanyId.isEmpty) {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][REFRESH_SKIP] reason=missing_company_context',
      );
      return;
    }
    if (_isBridgeBootstrapFreshForCompany(activeCompanyId)) {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][REFRESH_SKIP] reason=fresh_bootstrap company=${_maskBridgeDriverIdGlobal(activeCompanyId)}',
      );
      return;
    }
    final hasToken = await _hasUsableCompanyBootstrapToken(
      reason: 'driver_switch_candidates',
    );
    if (!hasToken) {
      debugPrint('[DRIVER_OWNER_BRIDGE][REFRESH_SKIP] reason=no_company_token');
      return;
    }
    // Picker refresh must never re-bootstrap the standalone driver session;
    // refreshing the candidate list does not require running fleet validation.
    final hydrated = await _hydrateCompanyBootstrapFromActiveSession(
      reason: 'driver_switch_candidates',
      bootstrapDriverSession: false,
    );
    debugPrint('[DRIVER_OWNER_BRIDGE][REFRESH_DONE] ok=$hydrated');
  }

  String _driverPickerAvailabilityLabel(DriverProfile driver) {
    final normalized = normalizeDriverAvailabilityState(
      driver.availabilityStatus,
      fallback: 'available',
    );
    if (!driver.isActive) {
      return _tr(nl: 'Inactief', en: 'Inactive', fr: 'Inactif', es: 'Inactivo');
    }
    switch (normalized) {
      case 'paused':
        return _tr(
          nl: 'Gepauzeerd',
          en: 'Paused',
          fr: 'En pause',
          es: 'En pausa',
        );
      case 'busy':
        return _tr(nl: 'Bezet', en: 'Busy', fr: 'Occupe', es: 'Ocupado');
      default:
        return _tr(
          nl: 'Beschikbaar',
          en: 'Available',
          fr: 'Disponible',
          es: 'Disponible',
        );
    }
  }

  String _driverPickerVehicleLabel(DriverProfile driver) {
    final driverId = driver.id.trim();
    if (driverId.isEmpty) return '';
    for (final vehicle in vehiclesNotifier.value) {
      if (!vehicle.isActive) continue;
      if ((vehicle.driverId ?? '').trim() != driverId) continue;
      final name = vehicle.vehicleName.trim();
      final plate = vehicle.licensePlate.trim();
      if (name.isNotEmpty && plate.isNotEmpty) return '$name ($plate)';
      if (name.isNotEmpty) return name;
      if (plate.isNotEmpty) return plate;
      return vehicle.id.trim();
    }
    return '';
  }

  Future<DriverProfile?> _showDriverSwitchPickerForDashboard({
    required List<DriverProfile> selectableDrivers,
    required String currentDriverId,
  }) {
    return showModalBottomSheet<DriverProfile>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF121A2E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5B641), width: 1.15),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE5B641).withOpacity(0.12),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _tr(
                            nl: 'Kies chauffeurweergave',
                            en: 'Choose driver view',
                            fr: 'Choisir la vue chauffeur',
                            es: 'Elegir vista de conductor',
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close, color: Color(0xFFE5B641)),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0x22E5B641)),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: selectableDrivers.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0x16E5B641)),
                    itemBuilder: (itemContext, index) {
                      final driver = selectableDrivers[index];
                      final driverId = driver.id.trim();
                      final isCurrent =
                          driverId.isNotEmpty &&
                          currentDriverId.isNotEmpty &&
                          driverId == currentDriverId;
                      final vehicleLabel = _driverPickerVehicleLabel(driver);
                      final statusLabel = _driverPickerAvailabilityLabel(
                        driver,
                      );
                      final subtitleParts = <String>[
                        if (driver.employeeNumber.trim().isNotEmpty)
                          driver.employeeNumber.trim(),
                        if (vehicleLabel.isNotEmpty)
                          _tr(
                            nl: 'Voertuig: $vehicleLabel',
                            en: 'Vehicle: $vehicleLabel',
                            fr: 'Véhicule : $vehicleLabel',
                            es: 'Vehículo: $vehicleLabel',
                          ),
                        statusLabel,
                      ];
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.person_outline_rounded,
                          color: Color(0xFFE5B641),
                        ),
                        title: Text(
                          driver.fullName.trim().isEmpty
                              ? driver.employeeNumber.trim()
                              : driver.fullName.trim(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          subtitleParts.join(' • '),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 12,
                          ),
                        ),
                        trailing: isCurrent
                            ? Text(
                                _tr(
                                  nl: 'Huidig',
                                  en: 'Current',
                                  fr: 'Actuel',
                                  es: 'Actual',
                                ),
                                style: const TextStyle(
                                  color: Color(0xFFE5B641),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                              )
                            : null,
                        onTap: () => Navigator.of(sheetContext).pop(driver),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _changeDriverViewFromDashboard() async {
    if (!_canSwitchCompanyDriversFromDashboard()) return;
    if (widget.openedFromBusinessHome) {
      debugPrint('[DRIVER_VIEW_ORIGIN][SWITCH] source=business_home');
    }
    await _refreshDriverBridgeCandidatesIfNeeded();
    final currentDriverId = _effectiveCurrentDriverIdForBusinessPreview();
    _logCurrentDriverOrigin(reason: 'switch_candidates');
    final List<DriverProfile> selectableDrivers;
    if (widget.openedFromBusinessHome) {
      final scope = _activeBusinessPreviewScope();
      selectableDrivers =
          _resolveOperationalCockpitDriverBridgeCandidatesGlobal(
            companyId: scope?.companyId,
            excludeDriverId: currentDriverId,
            logCandidates: true,
          );
    } else {
      final candidateReport = _resolveDriverBridgeCandidatesReportGlobal(
        logCandidates: true,
        excludeDriverId: currentDriverId,
        requireEmployeeNumber: true,
      );
      selectableDrivers = candidateReport.selectable;
    }
    if (selectableDrivers.isEmpty) {
      debugPrint('[DRIVER_OWNER_BRIDGE][SKIP] reason=no_selectable_driver');
      _toast(
        widget.openedFromBusinessHome
            ? _tr(
                nl: 'Geen andere chauffeur met voertuigtoewijzing beschikbaar.',
                en: 'No other vehicle-assigned driver available.',
                fr: 'Aucun autre chauffeur avec véhicule assigné.',
                es: 'No hay otro conductor con vehículo asignado.',
              )
            : _tr(
                nl: 'Geen beschikbare chauffeursweergave gevonden.',
                en: 'No selectable driver view found.',
                fr: 'Aucune vue chauffeur disponible.',
                es: 'No se encontró vista de conductor seleccionable.',
              ),
      );
      return;
    }
    DriverProfile? selectedDriver;
    if (!mounted) return;
    debugPrint(
      '[DRIVER_VIEW_ORIGIN][PICKER_OPEN] source=${widget.openedFromBusinessHome ? "business_home" : "driver_home"} count=${selectableDrivers.length}',
    );
    selectedDriver = await _showDriverSwitchPickerForDashboard(
      selectableDrivers: selectableDrivers,
      currentDriverId: currentDriverId,
    );
    if (!mounted) return;
    if (selectedDriver == null) {
      debugPrint(
        '[DRIVER_VIEW_ORIGIN][PICKER_CANCELLED] source=${widget.openedFromBusinessHome ? "business_home" : "driver_home"}',
      );
      return;
    }
    debugPrint(
      '[DRIVER_VIEW_ORIGIN][PICKER_SELECTED] source=${widget.openedFromBusinessHome ? "business_home" : "driver_home"} driver=${_maskBridgeDriverIdGlobal(selectedDriver.id)}',
    );
    debugPrint(
      '[DRIVER_OWNER_BRIDGE][SELECT] driver=${_maskBridgeDriverIdGlobal(selectedDriver.id)} reason=manual_preview',
    );
    if (widget.openedFromBusinessHome) {
      _businessPreviewDriverId = selectedDriver.id.trim();
      activeDriverSessionNotifier.value =
          await _hydrateBusinessPreviewDriverSession(
            driver: selectedDriver,
            reason: 'preview_switch',
          );
      final scope = _activeBusinessPreviewScope();
      if (scope != null) {
        await _saveBusinessDriverPreviewFromProfileGlobal(
          selectedDriver,
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
        debugPrint(
          '[DRIVER_VIEW_ORIGIN][PREVIEW_SAVE] source=business_home driver=${_maskBridgeDriverIdGlobal(selectedDriver.id)}',
        );
      }
      _logCurrentDriverOrigin(reason: 'preview_save_applied');
      if (mounted) setState(() {});
      _reconcileDriverAvailability(
        source: 'local',
        reason: 'preview_switch',
        incomingStatus: normalizeDriverAvailabilityState(
          selectedDriver.availabilityStatus,
          fallback: 'available',
        ),
      );
      unawaited(
        _refreshDriverAvailabilityFromBackend(
          reason: 'preview_switch',
          force: true,
        ),
      );
      _logRidesHubVisibleCounts(source: 'preview_picker_selected');
      unawaited(
        _refreshBookings(force: true, trigger: 'preview_picker_selected'),
      );
      return;
    } else {
      await DriverSessionStore.instance.saveFromDriverProfile(selectedDriver);
      await DriverSessionStore.instance.bootstrap(driversNotifier.value);
    }
    if (!mounted) return;
    if (activeDriverSessionNotifier.value != null) {
      setAppRole(AppRole.driver);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DriverHomePage(
            openedFromBusinessHome: widget.openedFromBusinessHome,
          ),
        ),
      );
      return;
    }
    _toast(
      _tr(
        nl: 'Chauffeurweergave kon niet worden geladen.',
        en: 'Could not load driver view.',
        fr: 'Impossible de charger la vue chauffeur.',
        es: 'No se pudo cargar la vista de conductor.',
      ),
    );
  }

  String _dashboardAvatarLabel() {
    final raw = _dashboardDriverName().trim();
    if (raw.isEmpty) return 'D';
    final parts = raw
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return raw[0].toUpperCase();
  }

  Widget _dashboardAvatarFallback() {
    return Text(
      _dashboardAvatarLabel(),
      style: TextStyle(
        color: Colors.white.withOpacity(0.95),
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }

  Future<void> _handleDriverStatusAction() async {
    if (_driverAvailabilitySaving) return;
    final status = _dashboardDriverStatus();
    final activeRideStatus =
        status == _DriverDashboardStatus.busy ||
        status == _DriverDashboardStatus.waiting ||
        status == _DriverDashboardStatus.onTheWay;
    if (activeRideStatus) {
      _toast(
        _tr(
          nl: 'Je bent bezig met een rit.',
          en: 'You are currently on a ride.',
          fr: 'Vous etes en course.',
          es: 'Estas realizando un viaje.',
        ),
      );
      return;
    }
    final profile = _dashboardActiveDriverProfile();
    final currentOperational = normalizeDriverAvailabilityState(
      _resolvedOperationalAvailabilityForDriver(profile: profile),
      fallback: 'available',
    );
    final buttonAction = _dashboardAvailabilityButtonAction(
      availabilityStatus: currentOperational,
    );
    final desired = switch (buttonAction) {
      'resume' => 'available',
      'start_shift' => 'available',
      _ => 'paused',
    };
    if (profile != null && !profile.isActive && desired == 'available') {
      _toast(
        _tr(
          nl: 'Account is inactief. Vraag je bedrijf om activatie.',
          en: 'Your account is inactive. Ask your company to reactivate it.',
          fr: 'Votre compte est inactif. Demandez une réactivation.',
          es: 'Tu cuenta está inactiva. Solicita reactivación.',
        ),
      );
      return;
    }
    final safeDriverRef = _shortDriverIdForDiag(
      profile?.id ?? activeDriverSessionNotifier.value?.driverId ?? '',
    );
    debugPrint(
      '[DRIVER_AVAILABILITY][LOCAL_CHANGE] driver=$safeDriverRef status=$desired action=$buttonAction',
    );
    debugPrint('[DRIVER_AVAILABILITY][PAUSE_START] driver=$safeDriverRef');

    if (_isBusinessPreviewMode) {
      if (profile == null) return;
      final scope = _activeBusinessPreviewScope();
      var companyToken =
          (activeCompanySessionNotifier.value?.companySessionToken ?? '')
              .trim();
      if (companyToken.isEmpty && scope != null) {
        final resolved = await CompanySessionStore.instance
            .resolveCompanyBootstrapToken();
        companyToken = (resolved.token ?? '').trim();
      }
      if (scope == null || companyToken.isEmpty) {
        _toast(
          _tr(
            nl: 'Deze actie vereist een actieve bedrijfssessie.',
            en: 'This action requires an active company session.',
            fr: 'Cette action nécessite une session entreprise active.',
            es: 'Esta acción requiere una sesión de empresa activa.',
          ),
        );
        return;
      }
      setState(() => _driverAvailabilitySaving = true);
      try {
        final optimistic = profile.copyWith(availabilityStatus: desired);
        _reconcileDriverAvailability(
          source: 'local',
          reason: 'business_preview_optimistic',
          incomingStatus: desired,
        );
        final result = await syncDriverStatusToBackend(
          optimistic,
          tenantId: scope.tenantId,
          companyId: scope.companyId,
          companySessionToken: companyToken,
        );
        debugPrint(
          '[DRIVER_AVAILABILITY][SYNC_SAVE] driver=$safeDriverRef status=$desired ok=${result.ok} source=company_admin',
        );
        if (!result.ok) {
          _reconcileDriverAvailability(
            source: 'local',
            reason: 'business_preview_rollback',
            incomingStatus: currentOperational,
          );
          _toast(
            _tr(
              nl: 'Status kon niet worden opgeslagen. Probeer opnieuw.',
              en: 'Could not save status. Please try again.',
              fr: 'Le statut n’a pas pu être enregistré.',
              es: 'No se pudo guardar el estado.',
            ),
          );
          return;
        }
        updateDriver(optimistic.id, optimistic, syncInventory: false);
        _reconcileDriverAvailability(
          source: 'backend',
          reason: 'business_preview_save',
          incomingStatus: desired,
        );
        unawaited(
          _refreshDriverAvailabilityFromBackend(
            reason: 'business_preview_save',
            force: true,
          ),
        );
        _toast(
          desired == 'paused'
              ? _tr(
                  nl: 'Status aangepast: Pauze',
                  en: 'Status updated: Pause',
                  fr: 'Statut mis a jour : Pause',
                  es: 'Estado actualizado: Pausa',
                )
              : _tr(
                  nl: 'Status aangepast: Klaar',
                  en: 'Status updated: Ready',
                  fr: 'Statut mis a jour : Pret',
                  es: 'Estado actualizado: Listo',
                ),
        );
      } finally {
        if (mounted) {
          setState(() => _driverAvailabilitySaving = false);
        } else {
          _driverAvailabilitySaving = false;
        }
      }
      return;
    }

    final sessionBeforeRecovery = activeDriverSessionNotifier.value;
    var token = (sessionBeforeRecovery?.driverSessionToken ?? '').trim();
    if (token.isEmpty) {
      var recoverySource = 'not_attempted';
      debugPrint(
        '[DRIVER_AVAILABILITY][RECOVER_ATTEMPT] has_session=${sessionBeforeRecovery != null} has_token_before=${token.isNotEmpty}',
      );
      try {
        final loadedSession = await DriverSessionStore.instance.load();
        recoverySource = loadedSession == null ? 'load_empty' : 'load_hit';
        if (loadedSession != null &&
            (loadedSession.driverSessionToken ?? '').trim().isNotEmpty) {
          // Re-publish the loaded session non-destructively without running
          // fleet validation; bootstrap() is reserved for app start.
          activeDriverSessionNotifier.value = loadedSession;
          recoverySource = '$recoverySource+notifier_publish';
        } else {
          // No usable session; bootstrap is now non-destructive on recoverable
          // failures and only deletes on expired/security_mismatch.
          await DriverSessionStore.instance.bootstrap(driversNotifier.value);
          recoverySource = '$recoverySource+bootstrap';
        }
      } catch (_) {
        recoverySource = 'load_bootstrap_error';
      }
      final sessionAfterRecovery = activeDriverSessionNotifier.value;
      token = (sessionAfterRecovery?.driverSessionToken ?? '').trim();
      debugPrint(
        '[DRIVER_AVAILABILITY][RECOVER_RESULT] has_session=${sessionAfterRecovery != null} has_token_after=${token.isNotEmpty}',
      );
      if (token.isEmpty) {
        final driverIdPresent =
            (sessionAfterRecovery?.driverId ?? '').trim().isNotEmpty ||
            (profile?.id ?? '').trim().isNotEmpty;
        debugPrint(
          '[DRIVER_AVAILABILITY][BLOCKED_NO_TOKEN] has_session=${sessionAfterRecovery != null} driver_id_present=$driverIdPresent source=$recoverySource',
        );
        _toast(
          _tr(
            nl: 'Chauffeurssessie ontbreekt. Log opnieuw in als chauffeur om je status te wijzigen.',
            en: 'Driver session missing. Please log in as driver again to change your status.',
            fr: 'Session chauffeur manquante. Reconnectez-vous comme chauffeur pour modifier votre statut.',
            es: 'Falta sesión de conductor. Vuelve a iniciar sesión como conductor para cambiar tu estado.',
          ),
        );
        return;
      }
    }
    setState(() => _driverAvailabilitySaving = true);
    try {
      _reconcileDriverAvailability(
        source: 'local',
        reason: 'optimistic',
        incomingStatus: desired,
      );
      debugPrint(
        '[DRIVER_AVAILABILITY][REQUEST] driver=$safeDriverRef status=$desired endpoint=/public/driver/availability',
      );
      final result = await syncPublicDriverAvailabilityToBackend(
        driverSessionToken: token,
        availabilityStatus: desired,
      );
      debugPrint(
        '[DRIVER_AVAILABILITY][RESPONSE] driver=$safeDriverRef status=${result.statusCode ?? 0} ok=${result.ok}',
      );
      if (!result.ok) {
        _reconcileDriverAvailability(
          source: 'local',
          reason: 'rollback',
          incomingStatus: currentOperational,
        );
        debugPrint(
          '[DRIVER_AVAILABILITY][FAILED] driver=$safeDriverRef error=${result.errorCode}',
        );
        _toast(
          _tr(
            nl: 'Status kon niet worden opgeslagen. Probeer opnieuw.',
            en: 'Could not save status. Please try again.',
            fr: 'Le statut n’a pas pu être enregistré.',
            es: 'No se pudo guardar el estado.',
          ),
        );
        return;
      }
      final savedStatus = normalizeDriverAvailabilityState(
        result.availabilityStatus,
        fallback: desired,
      );
      debugPrint(
        '[DRIVER_AVAILABILITY][SYNC_SAVE] driver=$safeDriverRef status=$savedStatus source=public_driver',
      );
      if (profile != null) {
        final updated = profile.copyWith(availabilityStatus: savedStatus);
        updateDriver(updated.id, updated, syncInventory: false);
        debugPrint(
          '[DRIVER_AVAILABILITY][ADMIN_VISIBLE] driver=$safeDriverRef availability=$savedStatus',
        );
      }
      _reconcileDriverAvailability(
        source: 'backend',
        reason: 'public_driver_save',
        incomingStatus: savedStatus,
      );
      if (savedStatus == 'paused') {
        debugPrint(
          '[DRIVER_AVAILABILITY][DISPATCH_EXCLUDE] driver=$safeDriverRef reason=paused',
        );
      }
      _toast(
        savedStatus == 'paused'
            ? _tr(
                nl: 'Status aangepast: Pauze',
                en: 'Status updated: Pause',
                fr: 'Statut mis a jour : Pause',
                es: 'Estado actualizado: Pausa',
              )
            : _tr(
                nl: 'Status aangepast: Klaar',
                en: 'Status updated: Ready',
                fr: 'Statut mis a jour : Pret',
                es: 'Estado actualizado: Listo',
              ),
      );
    } finally {
      if (mounted) {
        setState(() => _driverAvailabilitySaving = false);
      } else {
        _driverAvailabilitySaving = false;
      }
    }
  }

  void _showDashboardMoreSheet() {
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    final sheetGradient = isMiddayGold
        ? _middayGoldSurfaceGradient(soft: true)
        : (isMidnightBlue
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF020711),
                    Color(0xFF07111F),
                    Color(0xFF0B1B33),
                  ],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF101113), Color(0xFF0D0E11)],
                ));
    final sheetBorder = isMiddayGold
        ? _middayGoldBorderColor(0.34)
        : (isMidnightBlue
              ? _midnightBlueBorderColor(0.40)
              : Colors.white.withOpacity(0.10));
    final iconAccent = isMidnightBlue
        ? _midnightBlueAccent()
        : (isMiddayGold ? const Color(0xFFE8C57E) : const Color(0xFFFFD36A));
    final titleColor = isMiddayGold
        ? _middayGoldTextPrimary()
        : (isMidnightBlue ? _midnightBlueTextPrimary() : Colors.white);
    final subtitleColor = isMiddayGold
        ? _middayGoldTextMuted().withOpacity(0.92)
        : (isMidnightBlue
              ? _midnightBlueTextMuted().withOpacity(0.92)
              : Colors.white.withOpacity(0.62));

    // `isScrollControlled: true` lifts the default 9/16-of-screen cap so the
    // sheet can grow tall enough to fit every menu item plus the Android
    // system navigation inset. `constraints` keep the top of the sheet below
    // the status bar so it never looks fullscreen. The inner
    // `SingleChildScrollView` is the actual overflow guarantee for very small
    // phones (e.g. compact 5" devices in landscape); on regular phones it
    // never scrolls because the column already fits.
    final screenHeight = MediaQuery.of(context).size.height;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        // `SafeArea(top: false, bottom: true)` is what pulls the last
        // `ListTile` ("Terug naar startpagina") above the system nav bar.
        // Without `isScrollControlled: true` above, the sheet was clipped
        // before this padding could take effect.
        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              gradient: sheetGradient,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              border: Border.all(color: sheetBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr(nl: 'Meer', en: 'More', fr: 'Plus', es: 'Mas'),
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.calculate_rounded, color: iconAccent),
                      title: Text(
                        _tr(
                          nl: 'Prijs berekenen',
                          en: 'Fare calculator',
                          fr: 'Calcul de tarif',
                          es: 'Calcular tarifa',
                        ),
                        style: TextStyle(color: titleColor),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _openCalculatorFromDashboard();
                      },
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.receipt_long_outlined,
                        color: iconAccent,
                      ),
                      title: Text(
                        _tr(
                          nl: 'Ritbonnen / bewijzen',
                          en: 'Receipts / proofs',
                          fr: 'Recus / preuves',
                          es: 'Recibos / comprobantes',
                        ),
                        style: TextStyle(color: titleColor),
                      ),
                      subtitle: Text(
                        _tr(
                          nl: 'Via afgewerkte ritten in historiek',
                          en: 'Via completed rides in history',
                          fr: 'Via les courses terminees',
                          es: 'Via viajes completados en historial',
                        ),
                        style: TextStyle(color: subtitleColor, fontSize: 11.5),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _openTripHistoryFromDashboard();
                      },
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.toggle_on_outlined,
                        color: iconAccent,
                      ),
                      title: Text(
                        _tr(
                          nl: 'Beschikbaarheid',
                          en: 'Availability',
                          fr: 'Disponibilite',
                          es: 'Disponibilidad',
                        ),
                        style: TextStyle(color: titleColor),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        unawaited(_handleDriverStatusAction());
                      },
                    ),
                    if (!widget.openedFromBusinessHome)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.palette_outlined,
                          color: iconAccent,
                        ),
                        title: Text(
                          _tr(
                            nl: 'Thema',
                            en: 'Theme',
                            fr: 'Theme',
                            es: 'Tema',
                          ),
                          style: TextStyle(color: titleColor),
                        ),
                        subtitle: Text(
                          _tr(
                            nl: 'Kies je persoonlijke chauffeurweergave',
                            en: 'Choose your personal driver theme',
                            fr: 'Choisissez votre theme chauffeur personnel',
                            es: 'Elige tu tema personal de conductor',
                          ),
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 11.5,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          unawaited(_showDriverAppThemeSelectorSheet());
                        },
                      ),
                    if (_canSwitchCompanyDriversFromDashboard())
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.switch_account_outlined,
                          color: iconAccent,
                        ),
                        title: Text(
                          _tr(
                            nl: 'Chauffeur wisselen',
                            en: 'Switch driver',
                            fr: 'Changer de chauffeur',
                            es: 'Cambiar conductor',
                          ),
                          style: TextStyle(color: titleColor),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          unawaited(_changeDriverViewFromDashboard());
                        },
                      ),
                    if (!widget.openedFromBusinessHome)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.swap_horiz, color: iconAccent),
                        title: Text(
                          _tr(
                            nl: 'Wissel chauffeur',
                            en: 'Switch driver',
                            fr: 'Changer de chauffeur',
                            es: 'Cambiar conductor',
                          ),
                          style: TextStyle(color: titleColor),
                        ),
                        subtitle: Text(
                          _tr(
                            nl: 'Meld een andere chauffeur aan',
                            en: 'Log in another driver',
                            fr: 'Connecter un autre chauffeur',
                            es: 'Iniciar sesion con otro conductor',
                          ),
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 11.5,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          unawaited(_handleStandaloneSwitchDriverRequest());
                        },
                      ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.home_outlined, color: iconAccent),
                      title: Text(
                        widget.openedFromBusinessHome
                            ? _tr(
                                nl: 'Terug naar bedrijfspagina',
                                en: 'Back to business page',
                                fr: 'Retour a la page entreprise',
                                es: 'Volver a la pagina de empresa',
                              )
                            : _tr(
                                nl: 'Terug naar startpagina',
                                en: 'Back to start page',
                                fr: "Retour a l'accueil",
                                es: 'Volver al inicio',
                              ),
                        style: TextStyle(color: titleColor),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (widget.openedFromBusinessHome) {
                          _goBackToBusinessPageFromDashboard();
                          return;
                        }
                        _goBackToStartFromDashboard();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDriverAppThemeSelectorSheet() async {
    if (widget.openedFromBusinessHome) return;

    final selectorTitle = _tr(
      nl: 'Persoonlijk thema',
      en: 'Personal theme',
      fr: 'Theme personnel',
      es: 'Tema personal',
    );

    String labelForVariant(DriverThemeVariant variant) {
      switch (variant) {
        case DriverThemeVariant.nightGold:
          return _tr(
            nl: 'Night Gold',
            en: 'Night Gold',
            fr: 'Night Gold',
            es: 'Night Gold',
          );
        case DriverThemeVariant.midnightBlue:
          return _tr(
            nl: 'Midnight Blue',
            en: 'Midnight Blue',
            fr: 'Midnight Blue',
            es: 'Midnight Blue',
          );
        case DriverThemeVariant.highContrast:
          return _tr(
            nl: 'Midday Gold',
            en: 'Midday Gold',
            fr: 'Midday Gold',
            es: 'Midday Gold',
          );
      }
    }

    String subtitleForVariant(DriverThemeVariant variant) {
      switch (variant) {
        case DriverThemeVariant.nightGold:
          return _tr(
            nl: 'Klassiek donker met gouden accenten',
            en: 'Classic dark with golden accents',
            fr: 'Sombre classique avec accents dores',
            es: 'Oscuro clasico con acentos dorados',
          );
        case DriverThemeVariant.midnightBlue:
          return _tr(
            nl: 'Diep blauw met cyaan accenten',
            en: 'Deep blue with cyan accents',
            fr: 'Bleu profond avec accents cyan',
            es: 'Azul profundo con acentos cian',
          );
        case DriverThemeVariant.highContrast:
          return _tr(
            nl: 'Espresso en champagne goud',
            en: 'Espresso and champagne gold',
            fr: 'Espresso et or champagne',
            es: 'Espresso y oro champan',
          );
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return ValueListenableBuilder<DriverThemeVariant>(
          valueListenable: driverAppThemeNotifier,
          builder: (context, selectedVariant, _) {
            final isMidnightBlue =
                selectedVariant == DriverThemeVariant.midnightBlue;
            final isMiddayGold =
                selectedVariant == DriverThemeVariant.highContrast;
            final sheetGradient = isMiddayGold
                ? _middayGoldSurfaceGradient(soft: true)
                : (isMidnightBlue
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF020711),
                            Color(0xFF07111F),
                            Color(0xFF0B1B33),
                          ],
                        )
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF101113), Color(0xFF0D0E11)],
                        ));
            final sheetBorder = isMiddayGold
                ? _middayGoldBorderColor(0.34)
                : (isMidnightBlue
                      ? _midnightBlueBorderColor(0.40)
                      : Colors.white.withOpacity(0.10));
            final iconAccent = isMidnightBlue
                ? _midnightBlueAccent()
                : (isMiddayGold
                      ? const Color(0xFFE8C57E)
                      : const Color(0xFFFFD36A));
            final titleColor = isMiddayGold
                ? _middayGoldTextPrimary()
                : (isMidnightBlue ? _midnightBlueTextPrimary() : Colors.white);
            final subtitleColor = isMiddayGold
                ? _middayGoldTextMuted().withOpacity(0.92)
                : (isMidnightBlue
                      ? _midnightBlueTextMuted().withOpacity(0.92)
                      : Colors.white.withOpacity(0.62));

            return SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  gradient: sheetGradient,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  border: Border.all(color: sheetBorder),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectorTitle,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final variant in DriverThemeVariant.values)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            selectedVariant == variant
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: iconAccent,
                          ),
                          title: Text(
                            labelForVariant(variant),
                            style: TextStyle(color: titleColor),
                          ),
                          subtitle: Text(
                            subtitleForVariant(variant),
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 11.5,
                            ),
                          ),
                          trailing: selectedVariant == variant
                              ? Icon(Icons.check_rounded, color: iconAccent)
                              : null,
                          onTap: () async {
                            final navigator = Navigator.of(ctx);
                            await saveDriverAppThemePreference(variant);
                            if (!mounted) return;
                            navigator.pop();
                            _toast(
                              _tr(
                                nl: 'Persoonlijk thema opgeslagen',
                                en: 'Personal theme saved',
                                fr: 'Theme personnel enregistre',
                                es: 'Tema personal guardado',
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _driverLanguagePill() {
    final code = currentLanguageCode.toUpperCase();
    return PopupMenuButton<String>(
      onSelected: setAppLanguageByCode,
      color: const Color(0xFF111827),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: const Color(0xFFFFD36A).withOpacity(0.35)),
      ),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'nl', child: Text('🇳🇱 NL')),
        PopupMenuItem(value: 'en', child: Text('🇬🇧 EN')),
        PopupMenuItem(value: 'fr', child: Text('🇫🇷 FR')),
        PopupMenuItem(value: 'es', child: Text('🇪🇸 ES')),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF111214),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x55FFD36A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.language_rounded,
              size: 13,
              color: Color(0xFFFFD36A),
            ),
            const SizedBox(width: 4),
            Text(
              code,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 10.3,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: Color(0xFFFFD36A),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverDashboardHeader() {
    final screenSize = MediaQuery.sizeOf(context);
    final screenW = screenSize.width;
    const driverLogoTargetMaxWidth = 260.0;
    const rightClusterWidth = 128.0;
    final isPhonePortrait = screenW < 600 && screenSize.height > screenW;
    final logoWidth = isPhonePortrait
        ? math.min(200.0, math.max(150.0, screenW - rightClusterWidth - 12.0))
        : math.min(driverLogoTargetMaxWidth, math.max(220.0, screenW - 118));
    final logoHeight = logoWidth * 0.39;
    final topBandHeight = math.max(62.0, logoHeight - 34.0);
    final headerLeftPull = isPhonePortrait ? -8.0 : -16.0;
    const headerTopPull = -8.0;
    final logoVisualLift = isPhonePortrait ? -6.0 : -14.0;
    final avatarPhotoPath = _dashboardAvatarPhotoPath();
    final avatarPhotoUrl = _dashboardAvatarNetworkUrl();
    final avatarDriverId = _effectiveActiveDriverIdForRideScope();
    final avatarCacheKey =
        '${avatarDriverId}_${avatarPhotoPath ?? avatarPhotoUrl ?? 'none'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: math.max(0.0, headerLeftPull),
            right: -headerLeftPull,
            top: math.max(0.0, headerTopPull),
          ),
          child: SizedBox(
            height: topBandHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: logoVisualLift,
                  left: 0,
                  right: isPhonePortrait ? rightClusterWidth : null,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: logoWidth,
                      height: logoHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _tenantLogo(
                          height: logoHeight,
                          fit: BoxFit.contain,
                          fallback: Image.asset(
                            kFluxidiLogoAsset,
                            height: logoHeight,
                            fit: BoxFit.contain,
                            alignment: Alignment.centerLeft,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 0,
                  child: Row(
                    children: [
                      _driverLanguagePill(),
                      const SizedBox(width: 8),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF16181B),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.20),
                              ),
                            ),
                            child: ClipOval(
                              child: SizedBox.expand(
                                child: avatarPhotoPath == null
                                    ? (avatarPhotoUrl == null
                                          ? Center(
                                              child: _dashboardAvatarFallback(),
                                            )
                                          : Image.network(
                                              avatarPhotoUrl,
                                              key: ValueKey<String>(
                                                avatarCacheKey,
                                              ),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Center(
                                                child:
                                                    _dashboardAvatarFallback(),
                                              ),
                                            ))
                                    : Image.file(
                                        File(avatarPhotoPath),
                                        key: ValueKey<String>(avatarCacheKey),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: _dashboardAvatarFallback(),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: -1,
                            bottom: 1,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2ECC71),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF050505),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDriverSummaryCards({
    required BookingItem? nextRide,
    bool compactLandscape = false,
    double? compactMinHeight,
  }) {
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    const summaryIconContainerSize = 52.0;
    const summaryIconGlyphSize = 30.0;
    const compactIconContainerSize = 36.0;
    const compactIconGlyphSize = 20.0;
    Widget card({
      required IconData icon,
      required String label,
      required String value,
      required Color accentColor,
      VoidCallback? onTap,
    }) {
      final iconChipColor = isMiddayGold
          ? Color.alphaBlend(
              accentColor.withOpacity(0.15),
              const Color(0xFF2A2216),
            )
          : (isMidnightBlue
                ? Color.alphaBlend(
                    accentColor.withOpacity(0.22),
                    const Color(0xFF0A1A30),
                  )
                : accentColor.withOpacity(0.16));
      final iconChipBorderColor = isMiddayGold
          ? Color.alphaBlend(
              accentColor.withOpacity(0.34),
              const Color(0x88E8C57E),
            )
          : (isMidnightBlue
                ? Color.alphaBlend(
                    accentColor.withOpacity(0.48),
                    _midnightBlueBorderColor(0.40),
                  )
                : accentColor.withOpacity(0.55));
      final cardBody = Container(
        constraints: compactLandscape && compactMinHeight != null
            ? BoxConstraints(minHeight: compactMinHeight)
            : null,
        padding: compactLandscape
            ? const EdgeInsets.fromLTRB(8, 6, 8, 6)
            : const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: (isMiddayGold || isMidnightBlue)
              ? null
              : const Color(0xFF111214),
          gradient: isMiddayGold
              ? _middayGoldSurfaceGradient()
              : (isMidnightBlue ? _midnightBlueSurfaceGradient() : null),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isMiddayGold
                ? _middayGoldBorderColor(0.40)
                : (isMidnightBlue
                      ? _midnightBlueBorderColor(0.42)
                      : Colors.white.withOpacity(0.10)),
            width: 1.0,
          ),
          boxShadow: (isMiddayGold || isMidnightBlue)
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.24),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: compactLandscape
            ? Row(
                children: [
                  Container(
                    width: compactIconContainerSize,
                    height: compactIconContainerSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconChipColor,
                      border: Border.all(color: iconChipBorderColor),
                    ),
                    child: Icon(
                      icon,
                      size: compactIconGlyphSize,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isMiddayGold
                            ? _middayGoldTextMuted()
                            : (isMidnightBlue
                                  ? _midnightBlueTextMuted()
                                  : Colors.white.withOpacity(0.78)),
                        fontSize: 11.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMiddayGold
                          ? _middayGoldTextPrimary()
                          : (isMidnightBlue
                                ? _midnightBlueTextPrimary()
                                : Colors.white),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: summaryIconContainerSize,
                    height: summaryIconContainerSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconChipColor,
                      border: Border.all(color: iconChipBorderColor),
                    ),
                    child: Icon(
                      icon,
                      size: summaryIconGlyphSize,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMiddayGold
                          ? _middayGoldTextPrimary()
                          : (isMidnightBlue
                                ? _midnightBlueTextPrimary()
                                : Colors.white),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMiddayGold
                          ? _middayGoldTextMuted()
                          : (isMidnightBlue
                                ? _midnightBlueTextMuted()
                                : Colors.white.withOpacity(0.66)),
                      fontSize: 10.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      );
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: isMiddayGold
            ? _middayGoldGradientFrame(
                radius: 13,
                stroke: 1.05,
                innerColor: const Color(0xFF19120B),
                child: cardBody,
              )
            : cardBody,
      );
    }

    return Row(
      children: [
        Expanded(
          child: card(
            icon: Icons.event_note_rounded,
            accentColor: const Color(0xFF2ECC71),
            label: _tr(
              nl: 'Gepland',
              en: 'Planned',
              fr: 'Prevues',
              es: 'Planificados',
            ),
            value: '${_visibleBookings.length}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: card(
            icon: Icons.check_circle_outline_rounded,
            accentColor: const Color(0xFF4C9BFF),
            label: _tr(
              nl: 'Voltooid',
              en: 'Completed',
              fr: 'Terminees',
              es: 'Completados',
            ),
            value: _completedTodayCardValue(),
            onTap: _openTripHistoryFromDashboard,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: card(
            icon: Icons.schedule_rounded,
            accentColor: const Color(0xFFFFB54D),
            label: _tr(
              nl: 'Volgende',
              en: 'Next',
              fr: 'Prochaine',
              es: 'Siguiente',
            ),
            value: _dashboardNextRideTime(nextRide),
          ),
        ),
      ],
    );
  }

  Widget _buildNextRideHeroCard({
    required BookingItem? nextRide,
    double? routePreviewHeight,
  }) {
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    if (nextRide == null) {
      Widget wrapMiddayButton(Widget button) {
        if (!isMiddayGold) return button;
        return _middayGoldGradientFrame(
          radius: 12,
          stroke: 1.0,
          innerColor: const Color(0xFF221B11),
          child: button,
        );
      }

      final panel = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (isMiddayGold || isMidnightBlue)
              ? null
              : const Color(0xFF101113),
          gradient: isMiddayGold
              ? _middayGoldSurfaceGradient()
              : (isMidnightBlue ? _midnightBlueSurfaceGradient() : null),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMiddayGold
                ? _middayGoldBorderColor(0.38)
                : (isMidnightBlue
                      ? _midnightBlueBorderColor(0.42)
                      : Colors.white.withOpacity(0.10)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tr(
                nl: 'Geen ritten gepland',
                en: 'No rides planned',
                fr: 'Aucune course planifiee',
                es: 'No hay viajes planificados',
              ),
              style: TextStyle(
                color: isMiddayGold
                    ? _middayGoldTextPrimary()
                    : (isMidnightBlue
                          ? _midnightBlueTextPrimary()
                          : Colors.white),
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _tr(
                nl: 'Haal nieuwe planning op of start een straatrit.',
                en: 'Fetch latest planning or start a direct ride.',
                fr: 'Actualisez le planning ou demarrez une course directe.',
                es: 'Actualiza la planificación o inicia un viaje directo.',
              ),
              style: TextStyle(
                color: isMiddayGold
                    ? _middayGoldTextMuted()
                    : (isMidnightBlue
                          ? _midnightBlueTextMuted()
                          : Colors.white.withOpacity(0.68)),
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: wrapMiddayButton(
                    OutlinedButton.icon(
                      style: isMiddayGold
                          ? _middayGoldOutlinedActionButtonStyle()
                          : (isMidnightBlue
                                ? _midnightBlueOutlinedActionButtonStyle()
                                : _ghostButtonStyle()),
                      onPressed: () =>
                          _refreshBookings(force: true, trigger: 'list_manual'),
                      icon: const Icon(Icons.refresh, size: 17),
                      label: Text(
                        _tr(
                          nl: 'Vernieuw',
                          en: 'Refresh',
                          fr: 'Actualiser',
                          es: 'Actualizar',
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: wrapMiddayButton(
                    FilledButton.icon(
                      style: isMiddayGold
                          ? _middayGoldFilledActionButtonStyle()
                          : (isMidnightBlue
                                ? _midnightBlueFilledActionButtonStyle()
                                : _startButtonStyle()),
                      onPressed: _openDirectRideEntry,
                      icon: const Icon(Icons.local_taxi_outlined, size: 18),
                      label: Text(
                        _tr(
                          nl: 'Straatrit starten',
                          en: 'Start direct ride',
                          fr: 'Demarrer course directe',
                          es: 'Iniciar viaje directo',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      return isMiddayGold
          ? _middayGoldGradientFrame(
              radius: 16,
              stroke: 1.1,
              innerColor: const Color(0xFF19120B),
              child: panel,
            )
          : panel;
    }

    final pickup = _formatPickup(nextRide.pickupIso);
    final from = (nextRide.from ?? '').trim().isNotEmpty ? nextRide.from! : '—';
    final to = (nextRide.to ?? '').trim().isNotEmpty ? nextRide.to! : '—';
    final tier = (nextRide.tier ?? 'premium').toUpperCase();
    final details = nextRide.details;
    String? detailText(List<String> keys) {
      for (final key in keys) {
        final value = details[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }

    num? detailNum(List<String> keys) {
      for (final key in keys) {
        final value = details[key];
        if (value is num) return value;
        if (value is String) {
          final parsed = num.tryParse(value.trim());
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    final returnRaw = detailText([
      'return_trip',
      'returnTrip',
      'round_trip',
      'roundTrip',
      'is_return',
      'isReturn',
    ]);
    final returnTrip = (returnRaw ?? '').toLowerCase();
    final hasReturnTrip =
        returnTrip == 'true' ||
        returnTrip == '1' ||
        returnTrip == 'yes' ||
        returnTrip == 'ja';
    final legType = (detailText(['leg_type', 'legType']) ?? '')
        .trim()
        .toLowerCase();
    final isOperationalLeg = nextRide.isOperationalLeg;
    String subtypeLabel() {
      if (isOperationalLeg) {
        if (legType == 'return') {
          return _tr(
            nl: 'Terugrit',
            en: 'Return ride',
            fr: 'Trajet retour',
            es: 'Viaje de vuelta',
          );
        }
        return _tr(
          nl: 'Heenrit',
          en: 'Outbound ride',
          fr: 'Trajet aller',
          es: 'Viaje de ida',
        );
      }
      return hasReturnTrip
          ? _tr(nl: 'Retour', en: 'Return', fr: 'Retour', es: 'Regreso')
          : _tr(nl: 'Enkel', en: 'One-way', fr: 'Aller simple', es: 'Solo ida');
    }

    String? serviceChipLabel() {
      final raw =
          (detailText([
                    'service',
                    'service_type',
                    'serviceType',
                    'booking_type',
                    'bookingType',
                  ]) ??
                  '')
              .trim()
              .toLowerCase();
      if (raw.isEmpty) return null;
      if (raw.startsWith('airport') || raw.contains('luchthaven')) {
        return _tr(
          nl: 'Luchthavenvervoer',
          en: 'Airport transfer',
          fr: 'Transfert aeroport',
          es: 'Traslado al aeropuerto',
        );
      }
      return raw
          .replaceAll('_', ' ')
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .map(
            (p) => p.length == 1
                ? p.toUpperCase()
                : '${p[0].toUpperCase()}${p.substring(1)}',
          )
          .join(' ');
    }

    final serviceLabel = serviceChipLabel();
    final distanceKm = detailNum([
      'distance_km',
      'distanceKm',
      'distance',
      'route_distance_km',
    ]);
    final durationMin = detailNum([
      'duration_min',
      'durationMin',
      'duration_minutes',
      'duration',
      'estimated_duration_min',
    ]);
    final extraService = detailText([
      'extra_service',
      'extraService',
      'service',
      'service_label',
      'serviceLabel',
      'service_type',
      'serviceType',
      'ride_type',
      'rideType',
    ]);
    final statusText = _rideStatusLabel(
      _effectiveStatusFor(nextRide) ?? 'PENDING',
    );
    Widget metaChip({IconData? icon, required String text}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          gradient: isMiddayGold
              ? _middayGoldSurfaceGradient(soft: true)
              : (isMidnightBlue
                    ? _midnightBlueSurfaceGradient(soft: true)
                    : null),
          color: (isMiddayGold || isMidnightBlue)
              ? null
              : const Color(0xFF17191C),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isMiddayGold
                ? _middayGoldBorderColor(0.40)
                : (isMidnightBlue
                      ? _midnightBlueBorderColor(0.45)
                      : const Color(0x33FFD36A)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 12,
                color: isMiddayGold
                    ? const Color(0xFFE8C57E)
                    : (isMidnightBlue
                          ? _midnightBlueAccent()
                          : const Color(0xFFFFD36A)),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              text,
              style: TextStyle(
                color: isMiddayGold
                    ? _middayGoldTextPrimary()
                    : (isMidnightBlue
                          ? _midnightBlueTextPrimary()
                          : const Color(0xFFF2D691)),
                fontSize: 10.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    Widget infoLine({
      required IconData icon,
      required String text,
      Color color = const Color(0xFFFFD36A),
    }) {
      return Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMiddayGold
                    ? _middayGoldTextMuted()
                    : (isMidnightBlue
                          ? _midnightBlueTextMuted()
                          : const Color(0xFFF3D486)),
                fontSize: 10.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isMiddayGold || isMidnightBlue)
            ? null
            : const Color(0xFF101113),
        gradient: isMiddayGold
            ? _middayGoldSurfaceGradient()
            : (isMidnightBlue ? _midnightBlueSurfaceGradient() : null),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMiddayGold
              ? _middayGoldBorderColor(0.44)
              : (isMidnightBlue
                    ? _midnightBlueBorderColor(0.45)
                    : const Color(0x55FFD36A)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _tr(
                    nl: 'Volgende rit',
                    en: 'Next ride',
                    fr: 'Prochaine course',
                    es: 'Siguiente viaje',
                  ),
                  style: TextStyle(
                    color: isMiddayGold
                        ? _middayGoldTextPrimary()
                        : (isMidnightBlue
                              ? _midnightBlueTextPrimary()
                              : const Color(0xFFFFD36A).withOpacity(0.95)),
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              metaChip(
                icon: Icons.schedule,
                text: pickup == '—' ? statusText : pickup,
              ),
            ],
          ),
          const SizedBox(height: 9),
          infoLine(
            icon: Icons.radio_button_checked,
            text: from,
            color: isMidnightBlue
                ? _midnightBlueAccent()
                : const Color(0xFFFFD36A),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(
              Icons.south_rounded,
              size: 14,
              color: isMiddayGold
                  ? _middayGoldTextMuted().withOpacity(0.50)
                  : (isMidnightBlue
                        ? _midnightBlueTextMuted().withOpacity(0.58)
                        : Colors.white.withOpacity(0.35)),
            ),
          ),
          const SizedBox(height: 2),
          infoLine(
            icon: Icons.flag_rounded,
            text: to,
            color: isMidnightBlue
                ? _midnightBlueAccent()
                : const Color(0xFFFFD36A),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              metaChip(icon: Icons.workspace_premium_rounded, text: tier),
              metaChip(
                icon: Icons.person_rounded,
                text: '${nextRide.pax ?? 0} pax',
              ),
              metaChip(
                icon: Icons.luggage_rounded,
                text: '${nextRide.bags ?? 0} bagage',
              ),
              metaChip(
                icon: Icons.compare_arrows_rounded,
                text: subtypeLabel(),
              ),
              if (serviceLabel != null)
                metaChip(icon: Icons.local_taxi_rounded, text: serviceLabel),
              if (extraService != null)
                metaChip(
                  icon: Icons.miscellaneous_services_rounded,
                  text: extraService,
                ),
              metaChip(icon: Icons.info_outline_rounded, text: statusText),
              if (distanceKm != null)
                metaChip(
                  icon: Icons.straighten_rounded,
                  text: '${distanceKm.toStringAsFixed(1)} km',
                ),
              if (durationMin != null)
                metaChip(
                  icon: Icons.timer_outlined,
                  text: '${durationMin.round()} min',
                ),
              if (_driverDisplayPriceForBooking(nextRide) != null)
                metaChip(
                  icon: Icons.payments_outlined,
                  text: nextRide.isOperationalLeg
                      ? _fmtMoney(
                          _driverDisplayPriceForBooking(nextRide)!,
                          nextRide.currency ?? 'EUR',
                        )
                      : 'Totaal ${_fmtMoney(_driverDisplayPriceForBooking(nextRide)!, nextRide.currency ?? 'EUR')}',
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildNextRideRoutePreview(nextRide, height: routePreviewHeight),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: isMiddayGold
                      ? _middayGoldOutlinedActionButtonStyle()
                      : (isMidnightBlue
                            ? _midnightBlueOutlinedActionButtonStyle()
                            : _ghostButtonStyle()),
                  onPressed: () async {
                    await _goToRide(nextRide);
                    if (!mounted) return;
                    await _openNavigation();
                  },
                  icon: const Icon(Icons.navigation_outlined, size: 15),
                  label: const Text('Navigeer'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: isMiddayGold
                      ? _middayGoldFilledActionButtonStyle()
                      : (isMidnightBlue
                            ? _midnightBlueFilledActionButtonStyle()
                            : _startButtonStyle()),
                  onPressed: () async {
                    await _goToRide(nextRide);
                  },
                  icon: const Icon(Icons.chevron_right_rounded, size: 15),
                  label: const Text('Ga naar rit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverQuickActionsGrid({
    bool isTabletPortrait = false,
    double? tabletPortraitCardMinHeight,
    bool isTabletLandscape = false,
    int? forcedColumns,
    double? landscapeCardMinHeight,
    double? landscapeSpacing,
    bool compactLandscape = false,
    bool useImageBackgrounds = false,
    double? tabletPortraitSpacing,
    // Phone-portrait Visual layout overrides. Only honored when
    // isTabletPortrait == false && isTabletLandscape == false.
    bool isPhoneVisual = false,
    double? phoneVisualCardMinHeight,
    double? phoneVisualSpacing,
  }) {
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    const quickActionIconContainerSize = 56.0;
    const quickActionIconGlyphSize = 31.0;
    Widget quickAction({
      required IconData icon,
      required String title,
      String subtitle = '',
      required VoidCallback onTap,
      bool active = false,
      String? backgroundAsset,
    }) {
      final hasImageBackground =
          useImageBackgrounds && (backgroundAsset ?? '').trim().isNotEmpty;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: BoxConstraints(
            minHeight: isTabletPortrait
                ? (tabletPortraitCardMinHeight ?? 120.0)
                : isTabletLandscape
                ? (landscapeCardMinHeight ?? 98.0)
                : isPhoneVisual
                ? (phoneVisualCardMinHeight ?? 104.0)
                : 68.0,
          ),
          decoration: BoxDecoration(
            color: hasImageBackground
                ? (isMiddayGold
                      ? const Color(0xFF221B11).withOpacity(0.80)
                      : (isMidnightBlue
                            ? const Color(0xFF07111F).withOpacity(0.88)
                            : const Color(0xFF0A0A0A).withOpacity(0.88)))
                : (isMiddayGold
                      ? null
                      : (isMidnightBlue
                            ? null
                            : const Color(0xFF111111).withOpacity(0.96))),
            gradient: !hasImageBackground
                ? (isMiddayGold
                      ? _middayGoldSurfaceGradient()
                      : (isMidnightBlue
                            ? _midnightBlueSurfaceGradient()
                            : null))
                : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isTabletPortrait
                  ? Colors.transparent
                  : (active
                        ? (isMiddayGold
                              ? _middayGoldBorderColor(0.48)
                              : (isMidnightBlue
                                    ? _midnightBlueBorderColor(0.52)
                                    : const Color(0x66FFD36A)))
                        : (isMiddayGold
                              ? _middayGoldBorderColor(0.28)
                              : (isMidnightBlue
                                    ? _midnightBlueBorderColor(0.34)
                                    : Colors.white.withOpacity(0.12)))),
            ),
          ),
          foregroundDecoration: isTabletPortrait
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isMidnightBlue
                        ? _midnightBlueBorderColor(0.56)
                        : const Color(0xFFFFD36A).withOpacity(0.56),
                    width: 1.0,
                  ),
                )
              : null,
          child: Stack(
            children: [
              if (hasImageBackground)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Transform.scale(
                      scale: isTabletPortrait ? 1.055 : 1.0,
                      child: Image.asset(
                        backgroundAsset!,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              if (hasImageBackground)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(isMiddayGold ? 0.10 : 0.16),
                          Colors.black.withOpacity(isMiddayGold ? 0.20 : 0.26),
                          Colors.black.withOpacity(isMiddayGold ? 0.44 : 0.56),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(compactLandscape ? 8 : 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: quickActionIconContainerSize,
                      height: quickActionIconContainerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? (isMiddayGold
                                  ? const Color(0xFF3E2F1A)
                                  : (isMidnightBlue
                                        ? const Color(0xFF0F2747)
                                        : const Color(0xFF21180A)))
                            : (isMiddayGold
                                  ? const Color(0xFF2D2316)
                                  : (isMidnightBlue
                                        ? const Color(0xFF0A1A31)
                                        : const Color(0xFF17130B))),
                        border: Border.all(
                          color: active
                              ? (isMiddayGold
                                    ? const Color(0xCCE8C57E)
                                    : (isMidnightBlue
                                          ? _midnightBlueBorderColor(0.66)
                                          : const Color(0x88FFD36A)))
                              : (isMiddayGold
                                    ? const Color(0x88DDBB76)
                                    : (isMidnightBlue
                                          ? _midnightBlueBorderColor(0.40)
                                          : const Color(0x55FFD36A))),
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: isMiddayGold
                            ? _middayGoldTextPrimary()
                            : (isMidnightBlue
                                  ? _midnightBlueTextPrimary()
                                  : const Color(0xFFFFD36A)),
                        size: quickActionIconGlyphSize,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isMiddayGold
                                  ? _middayGoldTextPrimary()
                                  : (isMidnightBlue
                                        ? _midnightBlueTextPrimary()
                                        : Colors.white),
                              fontWeight: FontWeight.w800,
                              fontSize: 10.4,
                            ),
                          ),
                          if (subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isMiddayGold
                                    ? _middayGoldTextMuted()
                                    : (isMidnightBlue
                                          ? _midnightBlueTextMuted()
                                          : Colors.white.withOpacity(0.67)),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final gap = isTabletPortrait
            ? (tabletPortraitSpacing ?? 11.0)
            : isTabletLandscape
            ? (landscapeSpacing ?? 8.0)
            : isPhoneVisual
            ? (phoneVisualSpacing ?? 10.0)
            : 8.0;
        int columns;
        if (isTabletPortrait) {
          columns = 2;
        } else if (isTabletLandscape) {
          columns = forcedColumns ?? 3;
          final preferredWidth = (c.maxWidth - (gap * (columns - 1))) / columns;
          if (preferredWidth < 105.0) {
            columns = 2;
          }
        } else if (isPhoneVisual) {
          columns = 1;
        } else {
          const minTileWidth = 162.0;
          columns = (c.maxWidth / minTileWidth).floor();
          columns = columns.clamp(2, 4);
        }
        final width = (c.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.local_taxi_outlined,
                title: _tr(
                  nl: 'Straatrit',
                  en: 'Street ride',
                  fr: 'Course directe',
                  es: 'Viaje directo',
                ),
                onTap: _openDirectRideEntry,
                backgroundAsset: _driverAssetByTheme(
                  defaultAsset: 'assets/fluxidi/driver_action_street_ride.png',
                  midnightBlueAsset:
                      'assets/Midnight Bleu Chauffeur/driver_street_ride_midnight_blue.png',
                  middayGoldAsset:
                      'assets/Midday Gold Chauffeur/driver_street_ride_midday_gold.png',
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.calculate_rounded,
                title: _tr(
                  nl: 'Prijs berekenen',
                  en: 'Fare calculator',
                  fr: 'Calcul de tarif',
                  es: 'Calcular tarifa',
                ),
                onTap: _openCalculatorFromDashboard,
                backgroundAsset: _driverAssetByTheme(
                  defaultAsset:
                      'assets/fluxidi/driver_action_fare_calculator.png',
                  midnightBlueAsset:
                      'assets/Midnight Bleu Chauffeur/driver_fare_calculator_midnight_blue.png',
                  middayGoldAsset:
                      'assets/Midday Gold Chauffeur/driver_fare_calculator_midday_gold.png',
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.list_alt_rounded,
                title: _tr(
                  nl: 'Mijn ritten',
                  en: 'My rides',
                  fr: 'Mes courses',
                  es: 'Mis viajes',
                ),
                onTap: () => _openBookingsHubFromDashboard(
                  initialSegment: _DriverRidesHubSegment.myRides,
                ),
                backgroundAsset: _driverAssetByTheme(
                  defaultAsset: 'assets/fluxidi/driver_action_my_rides.png',
                  midnightBlueAsset:
                      'assets/Midnight Bleu Chauffeur/driver_my_rides_midnight_blue.png',
                  middayGoldAsset:
                      'assets/Midday Gold Chauffeur/driver_my_rides_midday_gold.png',
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.history_rounded,
                title: _tr(
                  nl: 'Historiek',
                  en: 'History',
                  fr: 'Historique',
                  es: 'Historial',
                ),
                onTap: _openTripHistoryFromDashboard,
                backgroundAsset: _driverAssetByTheme(
                  defaultAsset: 'assets/fluxidi/driver_action_history.png',
                  midnightBlueAsset:
                      'assets/Midnight Bleu Chauffeur/driver_history_midnight_blue.png',
                  middayGoldAsset:
                      'assets/Midday Gold Chauffeur/driver_history_midday_gold.png',
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.receipt_long_outlined,
                title: _tr(
                  nl: 'Ritbonnen',
                  en: 'Receipts',
                  fr: 'Recus',
                  es: 'Recibos',
                ),
                onTap: _openTripHistoryFromDashboard,
                backgroundAsset: _driverAssetByTheme(
                  defaultAsset: 'assets/fluxidi/driver_action_receipts.png',
                  midnightBlueAsset:
                      'assets/Midnight Bleu Chauffeur/driver_receipts_midnight_blue.png',
                  middayGoldAsset:
                      'assets/Midday Gold Chauffeur/driver_receipts_midday_gold.png',
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: quickAction(
                icon: Icons.folder_copy_outlined,
                title: _tr(
                  nl: 'Documenten',
                  en: 'Documents',
                  fr: 'Documents',
                  es: 'Documentos',
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DriverMyDocumentsPage(
                        themeListenable: _activeDriverThemeListenable,
                      ),
                    ),
                  );
                },
                backgroundAsset: _driverAssetByTheme(
                  defaultAsset: 'assets/fluxidi/driver_action_documents.png',
                  midnightBlueAsset:
                      'assets/Midnight Bleu Chauffeur/driver_documents_midnight_blue.png',
                  middayGoldAsset:
                      'assets/Midday Gold Chauffeur/driver_documents_midday_gold.png',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPremiumDriverDashboard() {
    const navIconSize = 25.0;
    final nextRide = _nextVisibleBookingForDashboard();
    final driverName = _dashboardDriverName();
    final statusKind = _dashboardDriverStatus();
    final actionLabel = _dashboardAvailabilityActionLabel();
    final statusReady = statusKind == _DriverDashboardStatus.ready;
    double clampDouble(double v, double min, double max) =>
        v < min ? min : (v > max ? max : v);
    final size = MediaQuery.sizeOf(context);
    final W = size.width;
    final H = size.height;
    final screenClass = FluxidiBreakpoints.classifyWidth(W);
    final isTabletPortrait =
        (screenClass == FluxidiScreenClass.tablet ||
            screenClass == FluxidiScreenClass.desktop) &&
        W < H &&
        H >= 900;
    final isTabletLandscape =
        (screenClass == FluxidiScreenClass.tablet ||
            screenClass == FluxidiScreenClass.desktop) &&
        W > H &&
        H >= 700;
    // Phone-portrait Visual layout opt-in. Strictly gated to phone portrait so
    // tablet portrait, tablet landscape, and phone landscape stay unchanged.
    final isPhonePortrait = !isTabletPortrait && !isTabletLandscape && W < H;
    final useDriverPhoneVisualMode =
        isPhonePortrait &&
        driverHomeMobileLayoutNotifier.value == DriverHomeMobileLayout.visual;
    final phoneVisualCardMinHeight = clampDouble(W * 0.28, 100.0, 116.0);
    const phoneVisualSpacing = 10.0;
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    final driverHeaderHeight = isTabletPortrait
        ? clampDouble(H * 0.24, 300.0, 360.0)
        : 0.0;
    final driverLandscapeHeaderHeight = isTabletLandscape
        ? clampDouble(H * 0.19, 140.0, 185.0)
        : 0.0;
    final driverQuickActionCardMinHeight = isTabletPortrait
        ? clampDouble(H * 0.155, 165.0, 188.0)
        : 68.0;
    final driverQuickActionGap = isTabletPortrait ? 8.0 : 8.0;
    final driverLandscapeQuickActionCardMinHeight = isTabletLandscape
        ? clampDouble(H * 0.175, 132.0, 162.0)
        : 98.0;
    final driverLandscapeQuickActionGap = isTabletLandscape ? 8.0 : 8.0;
    final driverLandscapeSummaryCardMinHeight = isTabletLandscape
        ? clampDouble(H * 0.09, 70.0, 86.0)
        : 70.0;
    final driverLandscapeRoutePreviewHeight = isTabletLandscape
        ? clampDouble(H * 0.24, 170.0, 220.0)
        : 136.0;
    final driverScrollBottomPadding = isTabletPortrait
        ? 20.0
        : (isTabletLandscape ? 18.0 : 10.0);
    Widget sectionTitle(String text) {
      return Text(
        text,
        style: TextStyle(
          color: isMiddayGold
              ? const Color(0xFFF3E5C4)
              : (isMidnightBlue ? _midnightBlueTextMuted() : Colors.white),
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    Widget navItem({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool active = false,
    }) {
      final color = isMiddayGold
          ? (active ? _middayGoldTextOnSelected() : _middayGoldTextMuted())
          : (isMidnightBlue
                ? (active
                      ? _midnightBlueTextPrimary()
                      : _midnightBlueTextMuted())
                : (active ? const Color(0xFFFFD36A) : Colors.white70));
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(
                horizontal: isMiddayGold ? 4 : (active ? 8 : 0),
                vertical: isMiddayGold ? 3 : (active ? 3 : 0),
              ),
              decoration: isMiddayGold
                  ? BoxDecoration(
                      gradient: active
                          ? _middayGoldSelectedSurfaceGradient()
                          : _middayGoldSurfaceGradient(soft: true),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: active
                            ? _middayGoldBorderColor(0.72)
                            : _middayGoldBorderColor(0.24),
                      ),
                      boxShadow: active
                          ? const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.20),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                    )
                  : (isMidnightBlue
                        ? BoxDecoration(
                            gradient: active
                                ? _midnightBlueSelectedSurfaceGradient()
                                : _midnightBlueSurfaceGradient(soft: true),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: active
                                  ? _midnightBlueBorderColor(0.65)
                                  : _midnightBlueBorderColor(0.30),
                            ),
                            boxShadow: active
                                ? const [
                                    BoxShadow(
                                      color: Color(0x66000000),
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ]
                                : [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.20),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                          )
                        : (active
                              ? BoxDecoration(
                                  gradient: _middayGoldMetallicGradient(),
                                  borderRadius: BorderRadius.circular(10),
                                )
                              : null)),
              child: Container(
                decoration: isMiddayGold
                    ? null
                    : (active
                          ? BoxDecoration(
                              color: const Color(0xFFF1D79A).withOpacity(0.16),
                              borderRadius: BorderRadius.circular(9),
                            )
                          : null),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isMiddayGold || isMidnightBlue)
                      Container(
                        width: 29,
                        height: 29,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isMiddayGold
                              ? (active
                                    ? _middayGoldTextOnSelected().withOpacity(
                                        0.14,
                                      )
                                    : _middayGoldBorderColor(0.10))
                              : (active
                                    ? _midnightBlueAccent().withOpacity(0.18)
                                    : _midnightBlueAccent().withOpacity(0.10)),
                          border: Border.all(
                            color: isMiddayGold
                                ? (active
                                      ? _middayGoldBorderColor(0.44)
                                      : _middayGoldBorderColor(0.22))
                                : (active
                                      ? _midnightBlueBorderColor(0.55)
                                      : _midnightBlueBorderColor(0.32)),
                          ),
                        ),
                        child: Icon(icon, size: 20, color: color),
                      )
                    else
                      Icon(icon, size: navIconSize, color: color),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 10.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget bottomNavRow() {
      return Row(
        children: [
          navItem(
            icon: Icons.home_filled,
            label: _tr(nl: 'Home', en: 'Home', fr: 'Accueil', es: 'Inicio'),
            active: true,
            onTap: () {},
          ),
          navItem(
            icon: Icons.list_alt_rounded,
            label: _tr(nl: 'Ritten', en: 'Rides', fr: 'Courses', es: 'Viajes'),
            onTap: () => _openBookingsHubFromDashboard(
              initialSegment: _DriverRidesHubSegment.available,
            ),
          ),
          navItem(
            icon: Icons.local_taxi_outlined,
            label: _tr(
              nl: 'Straatrit',
              en: 'Street ride',
              fr: 'Course directe',
              es: 'Viaje directo',
            ),
            onTap: _openDirectRideEntry,
          ),
          navItem(
            icon: Icons.menu_rounded,
            label: _tr(nl: 'Meer', en: 'More', fr: 'Plus', es: 'Mas'),
            onTap: _showDashboardMoreSheet,
          ),
        ],
      );
    }

    Widget driverIdentityBlock() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr(
              nl: 'Chauffeur',
              en: 'Driver',
              fr: 'Chauffeur',
              es: 'Conductor',
            ),
            style: TextStyle(
              color: isMiddayGold
                  ? const Color(0xFFD7C8AA)
                  : (isMidnightBlue
                        ? _midnightBlueTextMuted().withOpacity(0.90)
                        : Colors.white.withOpacity(0.72)),
              fontSize: 13.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.30,
            ),
          ),
          const SizedBox(height: 1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  driverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _handleDriverStatusAction,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: (isMiddayGold || isMidnightBlue)
                        ? null
                        : const Color(0xFF101113),
                    gradient: isMiddayGold
                        ? _middayGoldSurfaceGradient(soft: true)
                        : (isMidnightBlue
                              ? _midnightBlueSurfaceGradient(soft: true)
                              : null),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: statusReady
                          ? const Color(0x664CD964)
                          : (isMiddayGold
                                ? _middayGoldBorderColor(0.46)
                                : (isMidnightBlue
                                      ? _midnightBlueBorderColor(0.52)
                                      : const Color(0x66FFD36A))),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusReady
                              ? const Color(0xFF2ECC71)
                              : (isMidnightBlue
                                    ? _midnightBlueAccent()
                                    : const Color(0xFFFFD36A)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        actionLabel,
                        style: TextStyle(
                          color: statusReady
                              ? const Color(0xFFBCF6D0)
                              : (isMiddayGold
                                    ? _middayGoldTextPrimary()
                                    : (isMidnightBlue
                                          ? _midnightBlueTextPrimary()
                                          : const Color(0xFFFFE4A8))),
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return ColoredBox(
      color: isMiddayGold
          ? const Color(0xFF0F0D0A)
          : (isMidnightBlue
                ? const Color(0xFF050E1B)
                : const Color(0xFF050505)),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  14,
                  2,
                  14,
                  driverScrollBottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isTabletPortrait) ...[
                      Container(
                        height: driverHeaderHeight,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isMiddayGold
                                ? const Color(0xFFFFD36A).withOpacity(0.56)
                                : (isMidnightBlue
                                      ? _midnightBlueBorderColor(0.56)
                                      : const Color(0x55FFD36A)),
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              _driverAssetByTheme(
                                defaultAsset:
                                    'assets/fluxidi/driver_header_portrait_tablet.png',
                                midnightBlueAsset:
                                    'assets/Midnight Bleu Chauffeur/driver_home_header_midnight_blue.png',
                                middayGoldAsset:
                                    'assets/Midday Gold Chauffeur/driver_home_header_midday_gold.png',
                              ),
                              fit: BoxFit.cover,
                              alignment: Alignment.centerRight,
                              errorBuilder: (_, __, ___) => const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF101010),
                                      Color(0xFF07080C),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.16),
                                      Colors.black.withOpacity(0.26),
                                      Colors.black.withOpacity(0.56),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDriverDashboardHeader(),
                                    const Spacer(),
                                    driverIdentityBlock(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildDriverSummaryCards(nextRide: nextRide),
                      const SizedBox(height: 10),
                      _buildNextRideHeroCard(nextRide: nextRide),
                      const SizedBox(height: 10),
                      sectionTitle(
                        _tr(
                          nl: 'Snelle acties',
                          en: 'Quick actions',
                          fr: 'Actions rapides',
                          es: 'Acciones rapidas',
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDriverQuickActionsGrid(
                        isTabletPortrait: isTabletPortrait,
                        tabletPortraitCardMinHeight:
                            driverQuickActionCardMinHeight,
                        useImageBackgrounds: isTabletPortrait,
                        tabletPortraitSpacing: driverQuickActionGap,
                      ),
                      const SizedBox(height: 10),
                    ] else if (isTabletLandscape) ...[
                      Container(
                        height: driverLandscapeHeaderHeight,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isMiddayGold
                                ? const Color(0xFFFFD36A).withOpacity(0.56)
                                : (isMidnightBlue
                                      ? _midnightBlueBorderColor(0.56)
                                      : const Color(0x55FFD36A)),
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              _driverAssetByTheme(
                                defaultAsset:
                                    'assets/fluxidi/driver_header_landscape_tablet.png',
                                midnightBlueAsset:
                                    'assets/Midnight Bleu Chauffeur/driver_navigation_midnight_blue.png',
                                middayGoldAsset:
                                    'assets/Midday Gold Chauffeur/driver_navigation_midday_gold.png',
                              ),
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              errorBuilder: (_, __, ___) => const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF101010),
                                      Color(0xFF07080C),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.20),
                                      Colors.black.withOpacity(0.32),
                                      Colors.black.withOpacity(0.62),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  6,
                                  10,
                                  8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDriverDashboardHeader(),
                                    const SizedBox(height: 2),
                                    driverIdentityBlock(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 60,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDriverSummaryCards(
                                  nextRide: nextRide,
                                  compactLandscape: true,
                                  compactMinHeight:
                                      driverLandscapeSummaryCardMinHeight,
                                ),
                                const SizedBox(height: 10),
                                _buildNextRideHeroCard(
                                  nextRide: nextRide,
                                  routePreviewHeight:
                                      driverLandscapeRoutePreviewHeight,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            flex: 40,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                sectionTitle(
                                  _tr(
                                    nl: 'Snelle acties',
                                    en: 'Quick actions',
                                    fr: 'Actions rapides',
                                    es: 'Acciones rapidas',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildDriverQuickActionsGrid(
                                  isTabletLandscape: true,
                                  forcedColumns: 2,
                                  landscapeCardMinHeight:
                                      driverLandscapeQuickActionCardMinHeight,
                                  landscapeSpacing:
                                      driverLandscapeQuickActionGap,
                                  compactLandscape: true,
                                  useImageBackgrounds: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      _buildDriverDashboardHeader(),
                      const SizedBox(height: 1),
                      driverIdentityBlock(),
                      const SizedBox(height: 6),
                      _buildDriverSummaryCards(nextRide: nextRide),
                      const SizedBox(height: 10),
                      _buildNextRideHeroCard(nextRide: nextRide),
                      const SizedBox(height: 10),
                      sectionTitle(
                        _tr(
                          nl: 'Snelle acties',
                          en: 'Quick actions',
                          fr: 'Actions rapides',
                          es: 'Acciones rapidas',
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDriverQuickActionsGrid(
                        isTabletPortrait: isTabletPortrait,
                        tabletPortraitCardMinHeight:
                            driverQuickActionCardMinHeight,
                        useImageBackgrounds:
                            isTabletPortrait || useDriverPhoneVisualMode,
                        tabletPortraitSpacing: driverQuickActionGap,
                        isPhoneVisual: useDriverPhoneVisualMode,
                        phoneVisualCardMinHeight: phoneVisualCardMinHeight,
                        phoneVisualSpacing: phoneVisualSpacing,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: isMiddayGold
                  ? _middayGoldGradientFrame(
                      radius: 16,
                      stroke: 1.1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: _middayGoldSurfaceGradient(soft: true),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _middayGoldBorderColor(0.20),
                          ),
                        ),
                        child: bottomNavRow(),
                      ),
                    )
                  : (isMidnightBlue
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: _midnightBlueSurfaceGradient(
                                soft: true,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _midnightBlueBorderColor(0.24),
                              ),
                            ),
                            child: bottomNavRow(),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF101113),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                            child: bottomNavRow(),
                          )),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------
  // UI
  // -------------------------------

  Widget _buildStandaloneOperationalBlockPanel(String reason) {
    final message = reason == 'no_vehicle_assigned'
        ? _tr(
            nl: 'Geen voertuig toegewezen. Vraag je bedrijfsbeheerder om een voertuig toe te wijzen.',
            en: 'No vehicle assigned. Ask your company admin to assign a vehicle.',
            fr: 'Aucun véhicule assigné. Demandez à votre administrateur d’assigner un véhicule.',
            es: 'Sin vehículo asignado. Pide a tu administrador que asigne un vehículo.',
          )
        : _tr(
            nl: 'Chauffeurscockpit geblokkeerd. Neem contact op met je bedrijfsbeheerder.',
            en: 'Driver cockpit blocked. Contact your company admin.',
            fr: 'Cockpit chauffeur bloqué. Contactez votre administrateur.',
            es: 'Cockpit bloqueado. Contacta a tu administrador.',
          );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.88),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _buildHintPanel() {
    if (!widget.openedFromBusinessHome) {
      final blockReason =
          DriverSessionStore.instance.standaloneOperationalBlockReason;
      if ((blockReason ?? '').trim().isNotEmpty) {
        return _buildStandaloneOperationalBlockPanel(blockReason!.trim());
      }
    }
    return _buildPremiumDriverDashboard();
  }

  NavInstructionSnapshot _effectiveNavInstructionSnapshot() {
    NavInstructionSnapshot result;
    final snap = _navInstructionSnapshot;
    if (snap != null && snap.hasInstruction) {
      if (_nextStepIndex >= 0 && _nextStepIndex < _routeSteps.length) {
        result = applyDriverNavInstructionDisplayLines(
          snapshot: snap,
          step: _routeSteps[_nextStepIndex],
        );
      } else {
        result = snap;
      }
    } else {
      final instruction = (_nextNavInstruction ?? '').trim();
      final street = (_nextNavStreet ?? '').trim();
      if (instruction.isEmpty && street.isEmpty) {
        return snap ?? NavInstructionSnapshot.none;
      }
      final pseudoStep = DriverNavStep(
        lat: 0,
        lon: 0,
        instruction: instruction,
        street: street,
        type: _nextNavType ?? '',
        modifier: _nextNavModifier ?? '',
        distanceAlongRouteM: 0,
      );
      final rawPrimary = instruction.isNotEmpty
          ? instruction
          : _shortNavAction(instruction, _nextNavType, _nextNavModifier);
      final normalized = normalizeDriverInstructionDisplayLines(
        rawPrimary: rawPrimary,
        rawSecondary: street,
        step: pseudoStep,
      );
      result = NavInstructionSnapshot(
        distanceToManeuverMeters: _nextNavDistanceM ?? 0,
        primaryText: normalized.primary.isNotEmpty
            ? normalized.primary
            : street,
        secondaryText: normalized.secondary,
        maneuverType: _nextNavType ?? '',
        maneuverModifier: _nextNavModifier ?? '',
        roadName: street,
        isHighwayLike: false,
        lanes: const <DriverNavLaneGuidance>[],
        source: NavInstructionSource.step,
      );
    }

    return applyDriverNavInstructionPolicyFilter(
      snapshot: result,
      policy: _driverNavInstructionPolicy,
      liveRideActive: _liveRideActive,
      trustRouteSnap: _isActiveDriverNavEngineContext()
          ? (_lastNavConfidence?.trustRouteSnap ??
                _lastNavRouteProgress?.hasReliableSnap ??
                false)
          : _useMatchedVisual,
      trustInstruction: _lastNavConfidence?.trustInstruction ?? true,
      offRouteLikely: _lastNavRouteProgress?.offRouteLikely ?? _offRouteLikely,
      // NAV-R12-E2: route adaptation signals suppress stale maneuvers.
      routeDeviationLikely:
          _lastNavRouteProgress?.routeDeviationLikely ?? false,
      oppositeDirectionLikely:
          _lastNavRouteProgress?.oppositeDirectionLikely ?? false,
      backwardProgressLikely:
          _lastNavRouteProgress?.backwardProgressLikely ?? false,
      reroutePending: _isRerouting,
      forwardProgress: _lastNavRouteProgress?.forwardProgress ?? true,
      predictionActive: _lastNavMotionPrediction?.predictionActive ?? false,
      routeConfidence: _lastNavRouteProgress?.confidence,
      instructionConfidenceScore: _lastNavConfidence?.instructionScore,
      speedKmh: _lastPos != null ? _speedKmhFor(_lastPos!) : null,
      tr: _tr,
    );
  }

  String _navBannerSecondaryFromSnapshot(NavInstructionSnapshot snap) {
    final secondary = snap.secondaryText.trim();
    final primary = snap.primaryText.trim();
    if (secondary.isEmpty || secondary == primary) return '';
    if (primary.toLowerCase().contains(secondary.toLowerCase())) return '';
    return secondary;
  }

  bool _showNavInstructionBanner() {
    if (_cameraMode != _CameraMode.follow) return false;
    if (_isRerouting) return false;
    final snap = _navInstructionSnapshot;
    if (snap != null && snap.hasInstruction) return true;
    return (_nextNavInstruction ?? '').trim().isNotEmpty;
  }

  bool _showNavComplexityCaution() {
    return _cameraMode == _CameraMode.follow &&
        _lastNavCautionState.shouldShowCaution;
  }

  Widget _buildNavComplexityCautionBanner({
    required bool compact,
    required bool isTablet,
    bool topRowLandscape = false,
  }) {
    return DriverNavComplexityCautionBanner(
      compact: compact,
      isTablet: isTablet,
      topRowLandscape: topRowLandscape,
      title: navComplexityCautionLocalizedText(field: 'title', tr: _tr),
      body: navComplexityCautionLocalizedText(field: 'body', tr: _tr),
      themeListenable: _activeDriverThemeListenable,
    );
  }

  Widget _wrapNavBannerWithComplexityCaution({
    required Widget banner,
    required bool compact,
    required bool isTablet,
    bool topRowLandscape = false,
  }) {
    if (!_showNavComplexityCaution()) return banner;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        banner,
        SizedBox(height: topRowLandscape ? 4 : 6),
        _buildNavComplexityCautionBanner(
          compact: compact,
          isTablet: isTablet,
          topRowLandscape: topRowLandscape,
        ),
      ],
    );
  }

  Widget _buildTurnInstructionBanner({
    required bool compact,
    required bool isTablet,
    bool topRowLandscape = false,
  }) {
    final snapshot = _effectiveNavInstructionSnapshot();
    final distanceText = formatManeuverDistance(
      snapshot.distanceToManeuverMeters,
    );
    final primaryText = snapshot.primaryText.trim();
    final secondaryText = _navBannerSecondaryFromSnapshot(snapshot);
    final distancePrefix = _tr(nl: 'Over', en: 'In', fr: 'Dans', es: 'En');
    final isArrival = driverNavTypeIsArrival(snapshot.maneuverType);
    final icon = driverManeuverIconData(
      snapshot.maneuverType,
      snapshot.maneuverModifier,
      primaryText,
    );
    return DriverTurnInstructionBanner(
      themeListenable: _activeDriverThemeListenable,
      compact: compact,
      isTablet: isTablet,
      topRowLandscape: topRowLandscape,
      isArrival: isArrival,
      isHighwayLike: snapshot.isHighwayLike,
      distancePrefix: distancePrefix,
      distanceText: distanceText,
      primaryText: primaryText,
      secondaryText: secondaryText,
      subText: snapshot.subText,
      icon: icon,
      lanes: snapshot.lanes,
      maneuverModifier: snapshot.maneuverModifier,
    );
  }

  Widget _buildNavLoadingBanner({
    required bool compact,
    required bool isTablet,
    bool topRowLandscape = false,
  }) {
    final text = _isRerouting
        ? _tr(
            nl: 'Route herberekenen…',
            en: 'Recalculating route…',
            fr: 'Recalcul de l\'itinéraire…',
            es: 'Recalculando ruta…',
          )
        : _tr(
            nl: 'Route-instructies worden geladen…',
            en: 'Loading route instructions…',
            fr: 'Chargement des instructions…',
            es: 'Cargando instrucciones…',
          );
    return DriverNavLoadingBanner(
      compact: compact,
      isTablet: isTablet,
      topRowLandscape: topRowLandscape,
      text: text,
      themeListenable: _activeDriverThemeListenable,
    );
  }

  Widget _buildNoNavInstructionsBanner({
    required bool compact,
    required bool isTablet,
    bool topRowLandscape = false,
  }) {
    return DriverNoNavInstructionsBanner(
      compact: compact,
      isTablet: isTablet,
      topRowLandscape: topRowLandscape,
      text: _tr(
        nl: 'Volg de route',
        en: 'Follow the route',
        fr: 'Suivez l\'itinéraire',
        es: 'Sigue la ruta',
      ),
      themeListenable: _activeDriverThemeListenable,
    );
  }

  Widget? _buildFollowNavBannerForTopRow({required bool isTablet}) {
    if (_cameraMode != _CameraMode.follow) return null;
    if (_showNavInstructionBanner()) {
      return _wrapNavBannerWithComplexityCaution(
        banner: _buildTurnInstructionBanner(
          compact: true,
          isTablet: isTablet,
          topRowLandscape: true,
        ),
        compact: true,
        isTablet: isTablet,
        topRowLandscape: true,
      );
    }
    if (_navStepsLoading ||
        _isRerouting ||
        _navInstructionSnapshot?.source == NavInstructionSource.loading) {
      return _wrapNavBannerWithComplexityCaution(
        banner: _buildNavLoadingBanner(
          compact: true,
          isTablet: isTablet,
          topRowLandscape: true,
        ),
        compact: true,
        isTablet: isTablet,
        topRowLandscape: true,
      );
    }
    if (!_navStepsLoading && !_isRerouting && _routeSteps.isEmpty) {
      return _buildNoNavInstructionsBanner(
        compact: true,
        isTablet: isTablet,
        topRowLandscape: true,
      );
    }
    return null;
  }

  Widget _buildCollapsedNavMenuButton() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.26),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: IconButton(
            tooltip: 'Menu',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu_rounded, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedNavLogoCapsule({
    required bool isLandscape,
    required bool hasInlineBanner,
  }) {
    final logoWidth = isLandscape ? (hasInlineBanner ? 118.0 : 146.0) : 124.0;
    final logoHeight = isLandscape ? (hasInlineBanner ? 44.0 : 48.0) : 44.0;
    final imageHeight = isLandscape ? (hasInlineBanner ? 28.0 : 36.0) : 30.0;
    return IgnorePointer(
      child: Container(
        width: logoWidth,
        height: logoHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.38),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x66FFD36A)),
        ),
        child: Center(
          child: SizedBox(
            width: double.infinity,
            child: _tenantLogo(
              height: imageHeight,
              fit: BoxFit.contain,
              fallback: Image.asset(
                kFluxidiLogoAsset,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeCollapsedNavTopRow({required bool isTablet}) {
    final banner = _buildFollowNavBannerForTopRow(isTablet: isTablet);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildCollapsedNavMenuButton(),
        const SizedBox(width: 8),
        _buildCollapsedNavLogoCapsule(
          isLandscape: true,
          hasInlineBanner: banner != null,
        ),
        if (banner != null) ...[
          const SizedBox(width: 8),
          Expanded(child: banner),
        ],
      ],
    );
  }

  Widget _buildRecenterButton() {
    return Tooltip(
      message: kCenterOnMeLabel,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _centerOnMe,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF07142D).withOpacity(0.88),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFFD36A).withOpacity(0.55),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.my_location,
                  color: Color(0xFFFFD36A),
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _hintPanelText() {
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.en) {
      return 'Open menu -> Bookings to choose a ride and start it to drive.';
    }
    if (lang == AppLanguage.fr) {
      return 'Ouvrez le menu -> Courses pour choisir une course et la demarrer.';
    }
    if (lang == AppLanguage.es) {
      return 'Abre el menu -> Reservas para elegir un viaje e iniciarlo.';
    }
    return 'Open menu -> Ritten om een rit te kiezen en start hem om te rijden.';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final lastBuildLog = _lastDriverBuildLogAt;
    if (lastBuildLog == null || now.difference(lastBuildLog).inSeconds >= 5) {
      _lastDriverBuildLogAt = now;
      debugPrint(
        '[DRIVER][BUILD] live=$_liveRideActive mode=$_cameraMode loadingBookings=$_loadingBookings',
      );
    }
    final bool liveActive = _liveRideActive;
    final bool hasSelection = _activeBooking != null;
    final bool hasDirectDraft = _directRideDraft;
    final int state = liveActive
        ? 2
        : ((hasSelection || hasDirectDraft) ? 1 : 0);
    final bool showCockpit = liveActive || hasSelection || hasDirectDraft;
    final bool showNavQuickActions =
        showCockpit &&
        (_cameraMode == _CameraMode.follow ||
            _resolveExternalNavTarget() != null ||
            _routeCoords.length >= 2);
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bool collapseTopBarInLandscapeNav =
        isLandscape && _cameraMode == _CameraMode.follow;
    final bool collapseTopBarInPortraitNav =
        !isLandscape && _cameraMode == _CameraMode.follow;
    final double arrowBottom = isLandscape ? 88.0 : 138.0;
    final double safeBottomInset = MediaQuery.of(context).padding.bottom;
    // NAV-UI-R6F: floating recenter only exists outside route/nav context
    // (map actions are inside the cockpit bar there).
    final double recenterBottom = isLandscape
        ? (showCockpit ? 96.0 : 80.0) + safeBottomInset
        : (showCockpit ? 148.0 : 120.0) + safeBottomInset;
    final bool isTablet = screenW >= 600;
    final double navBannerPortraitMaxWidth = math.min(
      screenW * (isTablet ? 0.94 : 0.92),
      isTablet ? 820.0 : 700.0,
    );
    final bool collapsedNavHeader =
        collapseTopBarInLandscapeNav || collapseTopBarInPortraitNav;
    final double navBannerTop =
        MediaQuery.of(context).padding.top + (collapsedNavHeader ? 58 : 74);
    final bool hideMapUserPuck = _shouldHideMapboxUserLocationPuck();
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          // Map always at the back.
          Positioned.fill(child: _buildMapLayer()),
          if (!showCockpit)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: const Color(0xFF040404).withOpacity(0.985),
                ),
              ),
            ),

          // Top status / header (Fluxidi strip).
          if (showCockpit &&
              !collapseTopBarInLandscapeNav &&
              !collapseTopBarInPortraitNav)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 12,
              right: 12,
              child: _buildStatusStrip(state),
            ),
          if (showCockpit &&
              (collapseTopBarInLandscapeNav || collapseTopBarInPortraitNav))
            Positioned(
              top:
                  MediaQuery.of(context).padding.top +
                  (collapseTopBarInLandscapeNav ? 6 : 8),
              left: 10,
              right: collapseTopBarInLandscapeNav ? 10 : null,
              child: collapseTopBarInLandscapeNav
                  ? _buildLandscapeCollapsedNavTopRow(isTablet: isTablet)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCollapsedNavMenuButton(),
                        const SizedBox(width: 8),
                        _buildCollapsedNavLogoCapsule(
                          isLandscape: false,
                          hasInlineBanner: false,
                        ),
                      ],
                    ),
            ),
          if (_cameraMode == _CameraMode.follow &&
              _showNavInstructionBanner() &&
              !collapseTopBarInLandscapeNav)
            Positioned(
              top: navBannerTop,
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: navBannerPortraitMaxWidth,
                  ),
                  child: _wrapNavBannerWithComplexityCaution(
                    banner: _buildTurnInstructionBanner(
                      compact: false,
                      isTablet: isTablet,
                    ),
                    compact: false,
                    isTablet: isTablet,
                  ),
                ),
              ),
            ),
          if (_cameraMode == _CameraMode.follow &&
              !_showNavInstructionBanner() &&
              (_navStepsLoading ||
                  _isRerouting ||
                  _navInstructionSnapshot?.source ==
                      NavInstructionSource.loading) &&
              !collapseTopBarInLandscapeNav)
            Positioned(
              top: navBannerTop,
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: navBannerPortraitMaxWidth,
                  ),
                  child: _wrapNavBannerWithComplexityCaution(
                    banner: _buildNavLoadingBanner(
                      compact: false,
                      isTablet: isTablet,
                    ),
                    compact: false,
                    isTablet: isTablet,
                  ),
                ),
              ),
            ),
          if (_cameraMode == _CameraMode.follow &&
              !_showNavInstructionBanner() &&
              !_navStepsLoading &&
              !_isRerouting &&
              _routeSteps.isEmpty &&
              !collapseTopBarInLandscapeNav)
            Positioned(
              top: navBannerTop,
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: navBannerPortraitMaxWidth,
                  ),
                  child: _wrapNavBannerWithComplexityCaution(
                    banner: _buildNoNavInstructionsBanner(
                      compact: false,
                      isTablet: isTablet,
                    ),
                    compact: false,
                    isTablet: isTablet,
                  ),
                ),
              ),
            ),
          if (!hideMapUserPuck)
            Positioned(
              left: 0,
              right: 0,
              bottom: arrowBottom,
              child: IgnorePointer(
                child: Center(
                  child: Transform.rotate(
                    angle: _uiArrowBearing * math.pi / 180.0,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D8CFF).withOpacity(0.96),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.92),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.42),
                            blurRadius: 14,
                            spreadRadius: 1.0,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.navigation,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // NAV-UI-R6F: map actions live inside the bottom cockpit bar during
          // route/nav context; only the idle map keeps a floating recenter.
          if (_mapSupported && !showNavQuickActions)
            Positioned(
              right: 14,
              bottom: recenterBottom,
              child: _buildRecenterButton(),
            ),

          if (!showCockpit) Positioned.fill(child: _buildHintPanel()),

          // Bottom overlay layer (cockpit only).
          if (showCockpit)
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                // NAV-UI-R6F: cockpit is full width in both orientations and
                // hosts the compact map action icons (recenter, satellite,
                // offline, diagnostics, more) during route/nav context.
                child: SafeArea(
                  key: ValueKey<String>(
                    isLandscape ? 'landscape_cockpit' : 'portrait_cockpit',
                  ),
                  minimum: EdgeInsets.zero,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 8,
                        right: 8,
                        bottom: MediaQuery.of(context).viewInsets.bottom,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showNavQuickActions) _buildCockpitR9StatusChip(),
                          CockpitWidget(
                            embedded: true,
                            themeListenable: _activeDriverThemeListenable,
                            etaText: _etaText,
                            kmText: _kmRemainingText,
                            priceText: _cockpitPriceText,
                            tripStarted: _liveRideActive,
                            isWaiting: _isWaiting,
                            navActive: _cameraMode == _CameraMode.follow,
                            onNav: _openNavigation,
                            onStart: _handleCockpitStart,
                            onStop: _stopTrip,
                            onWait: _enterWaitMode,
                            onGo: _exitWaitMode,
                            secondaryActions: showNavQuickActions
                                ? _buildCockpitSecondaryActions()
                                : const <Widget>[],
                          ),
                          _buildDirectRideEstimatePanel(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapLayer() {
    final now = DateTime.now();
    final lastBuildLog = _lastMapWidgetBuildLogAt;
    if (lastBuildLog == null || now.difference(lastBuildLog).inSeconds >= 5) {
      _lastMapWidgetBuildLogAt = now;
      debugPrint(
        '[MAP][WIDGET_BUILD] mapSupported=$_mapSupported hasMap=${_map != null}',
      );
    }
    if (kIsWindows) {
      return _mapPlaceholder(
        title: 'Map unavailable on Windows',
        subtitle: 'Run on Android to see the live map.',
      );
    }

    if (kIsWeb) {
      return _mapPlaceholder(
        title: 'Map unavailable on Web',
        subtitle: 'Run on Android to see the live map.',
      );
    }

    return _stableMapWidget;
  }

  Widget _mapPlaceholder({required String title, required String subtitle}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.2,
          colors: [Color(0xFF141B2F), Color(0xFF070A10)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141B2F),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(subtitle, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopStatus(bool active) {
    if (!active) return const SizedBox.shrink();

    final eta = _fmtDur(_remainingSec());
    final km = _fmtRemainingKm();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F).withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 10, color: Color(0xFF4CD964)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tracking actief • Ping: $_lastPing • ETA: $eta • KM: $km',
              style: const TextStyle(fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFED6A5A).withOpacity(0.28),
              foregroundColor: const Color(0xFFFFB4AA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _stopTrip,
            child: Text(kStopShortLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsSheet(double screenH) {
    final padding = MediaQuery.of(context).padding.bottom;
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    final sheetGradient = isMiddayGold
        ? _middayGoldSurfaceGradient(soft: true)
        : (isMidnightBlue
              ? _midnightBlueSurfaceGradient(soft: true)
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF141B2F), Color(0xFF101113)],
                ));
    final sheetBorder = isMiddayGold
        ? _middayGoldBorderColor(0.34)
        : (isMidnightBlue ? _midnightBlueBorderColor(0.38) : Colors.white12);
    final sheetGlow = isMidnightBlue
        ? _midnightBlueAccent().withOpacity(0.20)
        : (isMiddayGold
              ? const Color(0x66E8C57E).withOpacity(0.34)
              : kFluxidiYellowSoft);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 14,
        bottom: 14 + padding,
      ),
      decoration: BoxDecoration(
        gradient: sheetGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: sheetBorder),
        boxShadow: [
          BoxShadow(blurRadius: 18, spreadRadius: 2, color: Colors.black54),
          BoxShadow(blurRadius: 26, spreadRadius: 1, color: sheetGlow),
        ],
      ),
      child: _buildBookingsList(screenH),
    );
  }

  Widget _buildBookingsList(double screenH) {
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    final panelGradient = isMiddayGold
        ? _middayGoldSurfaceGradient(soft: true)
        : (isMidnightBlue ? _midnightBlueSurfaceGradient(soft: true) : null);
    final panelFill = (isMiddayGold || isMidnightBlue)
        ? null
        : const Color(0xFF101113);
    final panelBorder = isMiddayGold
        ? _middayGoldBorderColor(0.34)
        : (isMidnightBlue
              ? _midnightBlueBorderColor(0.40)
              : kFluxidiYellow.withOpacity(0.30));
    final textPrimary = isMiddayGold
        ? _middayGoldTextPrimary()
        : (isMidnightBlue ? _midnightBlueTextPrimary() : Colors.white);
    final textMuted = isMiddayGold
        ? _middayGoldTextMuted()
        : (isMidnightBlue
              ? _midnightBlueTextMuted()
              : Colors.white.withOpacity(0.72));
    final spinnerColor = isMidnightBlue
        ? _midnightBlueAccent()
        : (isMiddayGold ? const Color(0xFFE8C57E) : kFluxidiYellow);
    final visibleBookings = _ridesHubSegmentBookings();
    final emptyTitle = switch (_ridesHubSegment) {
      _DriverRidesHubSegment.available => _tr(
        nl: 'Geen beschikbare ritten',
        en: 'No available rides',
        fr: 'Aucune course disponible',
        es: 'No hay viajes disponibles',
      ),
      _DriverRidesHubSegment.myRides => _tr(
        nl: 'Geen ritten klaar',
        en: 'No rides ready',
        fr: 'Aucune course prête',
        es: 'No hay viajes listos',
      ),
      _DriverRidesHubSegment.history => _tr(
        nl: 'Geen historiek',
        en: 'No history',
        fr: 'Aucun historique',
        es: 'Sin historial',
      ),
    };
    final emptyBody = switch (_ridesHubSegment) {
      _DriverRidesHubSegment.available => _tr(
        nl: 'Nieuwe beschikbare ritten verschijnen hier zodra ze door het systeem zijn vrijgegeven.',
        en: 'New available rides appear here once released by the system.',
        fr: 'Les nouvelles courses disponibles apparaissent ici une fois libérées par le système.',
        es: 'Los nuevos viajes disponibles aparecerán aquí cuando el sistema los publique.',
      ),
      _DriverRidesHubSegment.myRides => _tr(
        nl: 'Nieuwe boekingen verschijnen hier zodra ze aan jou of je bedrijf zijn gekoppeld.',
        en: 'New bookings appear here once they are assigned to you or your company.',
        fr: 'Les nouvelles réservations apparaissent ici dès qu’elles sont liées à vous ou à votre entreprise.',
        es: 'Las nuevas reservas aparecerán aquí cuando estén vinculadas a ti o a tu empresa.',
      ),
      _DriverRidesHubSegment.history => _tr(
        nl: 'Afgeronde ritten verschijnen hier zodra ze zijn voltooid of geannuleerd.',
        en: 'Completed rides appear here once they are finished or cancelled.',
        fr: 'Les courses terminées apparaissent ici une fois achevées ou annulées.',
        es: 'Los viajes completados aparecerán aquí cuando finalicen o se cancelen.',
      ),
    };
    final emptyInfoTitle = _tr(
      nl: 'Geen rit gevonden?',
      en: 'No ride found?',
      fr: 'Aucune course trouvée ?',
      es: '¿No encontraste un viaje?',
    );
    final emptyInfoBody = _tr(
      nl: 'Er zijn momenteel geen ritten beschikbaar. Trek omlaag om te vernieuwen.',
      en: 'There are currently no rides available. Pull down to refresh.',
      fr: 'Aucune course n’est disponible pour le moment. Tirez vers le bas pour actualiser.',
      es: 'Actualmente no hay viajes disponibles. Desliza hacia abajo para actualizar.',
    );
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: panelFill,
            gradient: panelGradient,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: panelBorder),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                _ridesSegmentChip(
                  label: _tr(
                    nl: 'Beschikbaar',
                    en: 'Available',
                    fr: 'Disponibles',
                    es: 'Disponibles',
                  ),
                  active: _ridesHubSegment == _DriverRidesHubSegment.available,
                  onTap: () {
                    if (_ridesHubSegment == _DriverRidesHubSegment.available) {
                      return;
                    }
                    debugPrint(
                      '[DRIVER_RIDES][SEGMENT] segment=${_DriverRidesHubSegment.available} source=hub_chip',
                    );
                    setState(
                      () => _ridesHubSegment = _DriverRidesHubSegment.available,
                    );
                    _markBookingsUiDirty();
                  },
                ),
                const SizedBox(width: 6),
                _ridesSegmentChip(
                  label: _tr(
                    nl: 'Mijn ritten',
                    en: 'My rides',
                    fr: 'Mes courses',
                    es: 'Mis viajes',
                  ),
                  active: _ridesHubSegment == _DriverRidesHubSegment.myRides,
                  onTap: () {
                    if (_ridesHubSegment == _DriverRidesHubSegment.myRides) {
                      return;
                    }
                    debugPrint(
                      '[DRIVER_RIDES][SEGMENT] segment=${_DriverRidesHubSegment.myRides} source=hub_chip',
                    );
                    setState(
                      () => _ridesHubSegment = _DriverRidesHubSegment.myRides,
                    );
                    _markBookingsUiDirty();
                    _maybeForceRefreshOnMyRidesOpen(source: 'hub_chip');
                  },
                ),
                const SizedBox(width: 6),
                _ridesSegmentChip(
                  label: _tr(
                    nl: 'Historiek',
                    en: 'History',
                    fr: 'Historique',
                    es: 'Historial',
                  ),
                  active: _ridesHubSegment == _DriverRidesHubSegment.history,
                  onTap: () {
                    debugPrint(
                      '[DRIVER_RIDES][SEGMENT] segment=${_DriverRidesHubSegment.history} source=hub_chip action=open_trip_history',
                    );
                    _openTripHistoryFromDashboard();
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_loadingBookings)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
            decoration: BoxDecoration(
              color: panelFill,
              gradient: panelGradient,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: panelBorder),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: spinnerColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _tr(
                    nl: 'Ritten worden geladen...',
                    en: 'Loading rides...',
                    fr: 'Chargement des courses...',
                    es: 'Cargando viajes...',
                  ),
                  style: TextStyle(
                    color: textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else if (_bookingsError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1212),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF7A2A2A).withOpacity(0.8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(
                    nl: 'Ritten konden niet geladen worden.',
                    en: 'Could not load rides.',
                    fr: 'Impossible de charger les courses.',
                    es: 'No se pudieron cargar los viajes.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFFFFB3B3),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Error: $_bookingsError',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ),
          )
        else if (visibleBookings.isEmpty)
          Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panelFill,
                  gradient: panelGradient,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: panelBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emptyTitle,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      emptyBody,
                      style: TextStyle(color: textMuted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: panelFill,
                  gradient: panelGradient,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isMiddayGold
                        ? _middayGoldBorderColor(0.28)
                        : (isMidnightBlue
                              ? _midnightBlueBorderColor(0.34)
                              : kFluxidiYellow.withOpacity(0.25)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emptyInfoTitle,
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      emptyInfoBody,
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 12.4,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              itemCount: visibleBookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final booking = visibleBookings[i];
                if (_ridesHubSegment == _DriverRidesHubSegment.available) {
                  return _buildAvailableUnassignedBookingCard(booking);
                }
                return _bookingCard(booking);
              },
            ),
          ),
      ],
    );
  }

  ({String label, String value}) _driverCardReferenceDisplay(BookingItem b) {
    final canonicalBookingId = _cleanBusinessReferenceText(b.bookingId) ?? '';
    final detailsMap = Map<String, dynamic>.from(b.details);
    if (canonicalBookingId.isNotEmpty) {
      detailsMap['booking_id'] = canonicalBookingId;
      detailsMap['bookingId'] = canonicalBookingId;
    }
    final maps = _referenceLookupMaps(<Map<String, dynamic>>[detailsMap]);
    final refs = _extractBusinessReferenceAliasesFromMaps(maps);
    final planning = refs.planning ?? '';
    final publicBooking =
        refs.publicBooking ?? refs.booking ?? refs.publicRef ?? '';

    String label;
    String value;
    if (planning.isNotEmpty) {
      label = _tr(
        nl: 'Planningnummer',
        en: 'Planning no.',
        fr: 'N° de planning',
        es: 'N.º de planificación',
      );
      value = planning;
    } else if (publicBooking.isNotEmpty) {
      label = _tr(
        nl: 'Boekingsnummer',
        en: 'Booking no.',
        fr: 'N° de réservation',
        es: 'N.º de reserva',
      );
      value = publicBooking;
    } else {
      label = _tr(
        nl: 'Interne boeking',
        en: 'Internal booking',
        fr: 'Réservation interne',
        es: 'Reserva interna',
      );
      value = canonicalBookingId.isEmpty ? b.shortId : canonicalBookingId;
    }
    debugPrint(
      '[RIDES][CARD_REF_SELECTED] booking=${_safeRefPreview(canonicalBookingId)} planning=$planning public=$publicBooking selected=$value',
    );
    return (label: label, value: value);
  }

  bool _bookingIsOperationalLeg(BookingItem b) {
    return b.isOperationalLeg;
  }

  bool _bookingIsRoundtripParent(BookingItem b) {
    final token =
        (b.details['is_roundtrip_parent'] ??
                b.details['isRoundtripParent'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    return token == 'true' || token == '1';
  }

  String _bookingLegType(BookingItem b) {
    return (b.details['leg_type'] ?? b.details['legType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  String _bookingLegLabel(BookingItem b) {
    final legType = _bookingLegType(b);
    if (legType == 'return') {
      return _tr(
        nl: 'Terugrit',
        en: 'Return ride',
        fr: 'Trajet retour',
        es: 'Viaje de vuelta',
      );
    }
    if (legType == 'outbound') {
      return _tr(
        nl: 'Heenrit',
        en: 'Outbound ride',
        fr: 'Trajet aller',
        es: 'Viaje de ida',
      );
    }
    return _tr(
      nl: 'Geplande rit',
      en: 'Planned ride',
      fr: 'Course planifiée',
      es: 'Viaje planificado',
    );
  }

  Widget _buildAvailableUnassignedBookingCard(BookingItem b) {
    debugPrint('[DRIVER_RIDES][AVAILABLE_CARD] booking_id=${b.bookingId}');
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    final cardPrimary = isMiddayGold
        ? _middayGoldTextPrimary()
        : (isMidnightBlue ? _midnightBlueTextPrimary() : Colors.white);
    final cardMuted = isMiddayGold
        ? _middayGoldTextMuted()
        : (isMidnightBlue
              ? _midnightBlueTextMuted()
              : Colors.white.withOpacity(0.66));
    final cardAccent = isMidnightBlue
        ? _midnightBlueAccent()
        : (isMiddayGold ? const Color(0xFFE8C57E) : const Color(0xFFFFD36A));
    final dt = _formatPickup(b.pickupIso);
    final cardReference = _driverCardReferenceDisplay(b);
    final customerName =
        _bookingScopeFirstText(_bookingScopeViewFor(b), const [
          ['customer_name'],
          ['customerName'],
          ['customer', 'name'],
          ['booking', 'customer_name'],
          ['booking', 'customerName'],
          ['booking', 'customer', 'name'],
        ]) ??
        '';
    final awaitingDispatchLabel = _tr(
      nl: 'Wacht op toewijzing',
      en: 'Awaiting dispatch',
      fr: 'En attente d\'assignation',
      es: 'En espera de asignacion',
    );
    final readOnlyHint = _tr(
      nl: 'Deze rit is zichtbaar maar nog niet aan jou toegewezen.',
      en: 'This ride is visible but not assigned to you yet.',
      fr: 'Cette course est visible mais pas encore assignee.',
      es: 'Este viaje es visible pero aun no esta asignado.',
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      decoration: BoxDecoration(
        gradient: isMiddayGold
            ? _middayGoldSurfaceGradient()
            : (isMidnightBlue
                  ? _midnightBlueSurfaceGradient()
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF151515), Color(0xFF0B0B0B)],
                    )),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isMiddayGold
              ? _middayGoldBorderColor(0.36)
              : (isMidnightBlue
                    ? _midnightBlueBorderColor(0.42)
                    : kFluxidiYellow.withOpacity(0.24)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pill(
            icon: Icons.schedule,
            text: dt,
            borderColor: isMidnightBlue
                ? _midnightBlueBorderColor(0.50)
                : const Color(0x55FFD36A),
            textColor: isMidnightBlue
                ? _midnightBlueTextPrimary()
                : const Color(0xFFFFD98A),
            compact: true,
          ),
          const SizedBox(height: 10),
          Text(
            b.from ?? '—',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cardPrimary,
              fontSize: 15.1,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            b.to ?? '—',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cardPrimary.withOpacity(0.92),
              fontSize: 15.0,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (customerName.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              '${_tr(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente')}: $customerName',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cardMuted.withOpacity(0.92),
                fontSize: 11.8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill(
                text: awaitingDispatchLabel,
                borderColor: const Color(0xFF52B6FF),
                textColor: const Color(0xFF9DD8FF),
                compact: true,
              ),
              if (_driverDisplayPriceForBooking(b) != null)
                _pill(
                  text: _fmtMoney(
                    _driverDisplayPriceForBooking(b)!,
                    b.currency ?? 'EUR',
                  ),
                  borderColor: isMidnightBlue
                      ? _midnightBlueBorderColor(0.50)
                      : const Color(0x55FFD36A),
                  textColor: cardAccent,
                  compact: true,
                ),
            ],
          ),
          if (cardReference.value.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${cardReference.label}: ${cardReference.value}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cardMuted.withOpacity(0.82),
                fontSize: 10.8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            readOnlyHint,
            style: TextStyle(
              color: cardMuted,
              fontSize: 12.2,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.hourglass_empty_rounded, size: 16),
              label: Text(
                awaitingDispatchLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _compactRideCardFilledStyle(ButtonStyle? base) {
    final compact = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    if (base == null) {
      return compact.copyWith(
        backgroundColor: MaterialStateProperty.all(kFluxidiYellow),
        foregroundColor: MaterialStateProperty.all(Colors.black),
      );
    }
    return base.merge(compact);
  }

  ButtonStyle _compactRideCardOutlinedStyle(ButtonStyle? base) {
    final compact = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return base == null ? compact : base.merge(compact);
  }

  Widget _buildRideCardPrimaryActions({
    required BookingItem b,
    required bool actionBusy,
    required String goToRideLabel,
    required ButtonStyle filledStyle,
    required ButtonStyle outlineStyle,
    required bool stackSecondaryActions,
  }) {
    void setCompleted() {
      if (b.isOperationalLeg && b.legId.trim().isNotEmpty) {
        _setOperationalLegStatus(b, 'COMPLETED');
      } else {
        _setBookingStatus(b, 'COMPLETED');
      }
    }

    void setCancelled() {
      if (b.isOperationalLeg && b.legId.trim().isNotEmpty) {
        _setOperationalLegStatus(b, 'CANCELLED');
      } else {
        _setBookingStatus(b, 'CANCELLED');
      }
    }

    final goButton = SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: filledStyle,
        onPressed: actionBusy ? null : () => _goToRide(b),
        icon: const Icon(Icons.navigation_rounded, size: 15),
        label: Text(
          goToRideLabel,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
        ),
      ),
    );
    final completeButton = OutlinedButton.icon(
      style: outlineStyle,
      onPressed: actionBusy ? null : setCompleted,
      icon: const Icon(Icons.check_circle_outline, size: 15),
      label: Text(
        kRideActionCompletedLabel,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5),
      ),
    );
    final cancelButton = OutlinedButton.icon(
      style: outlineStyle,
      onPressed: actionBusy ? null : setCancelled,
      icon: const Icon(Icons.cancel_outlined, size: 15),
      label: Text(
        kRideActionCancelledLabel,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5),
      ),
    );
    final deleteButton = IconButton(
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(36, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: actionBusy ? null : () => _confirmDelete(b),
      icon: const Icon(Icons.delete_outline, size: 18),
      tooltip: kRideDeleteLabel,
    );

    if (stackSecondaryActions) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          goButton,
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: completeButton),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: cancelButton),
              const SizedBox(width: 6),
              deleteButton,
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        goButton,
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: completeButton),
            const SizedBox(width: 6),
            Expanded(child: cancelButton),
            const SizedBox(width: 6),
            deleteButton,
          ],
        ),
      ],
    );
  }

  Widget _bookingCard(BookingItem b) {
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    final cardPrimary = isMiddayGold
        ? _middayGoldTextPrimary()
        : (isMidnightBlue ? _midnightBlueTextPrimary() : Colors.white);
    final cardMuted = isMiddayGold
        ? _middayGoldTextMuted()
        : (isMidnightBlue
              ? _midnightBlueTextMuted()
              : Colors.white.withOpacity(0.66));
    final cardAccent = isMidnightBlue
        ? _midnightBlueAccent()
        : (isMiddayGold ? const Color(0xFFE8C57E) : const Color(0xFFFFD36A));
    final cardActionStyle = isMiddayGold
        ? _middayGoldFilledActionButtonStyle()
        : (isMidnightBlue ? _midnightBlueFilledActionButtonStyle() : null);
    final cardOutlineStyle = isMiddayGold
        ? _middayGoldOutlinedActionButtonStyle()
        : (isMidnightBlue ? _midnightBlueOutlinedActionButtonStyle() : null);
    final dt = _formatPickup(b.pickupIso);
    final actionBusy = _bookingActionInFlight.contains(
      _bookingActionKeyForUi(b),
    );
    final cardReference = _driverCardReferenceDisplay(b);
    final isOperationalLeg = _bookingIsOperationalLeg(b);
    final isRoundtripParent = _bookingIsRoundtripParent(b);
    final legLabel = _bookingLegLabel(b);
    final parentBookingId =
        (b.details['parent_booking_id'] ?? b.details['parentBookingId'] ?? '')
            .toString()
            .trim();
    final customerName =
        _bookingScopeFirstText(_bookingScopeViewFor(b), const [
          ['customer_name'],
          ['customerName'],
          ['customer', 'name'],
          ['booking', 'customer_name'],
          ['booking', 'customerName'],
          ['booking', 'customer', 'name'],
        ]) ??
        '';

    return LayoutBuilder(
      builder: (context, c) {
        final compactPortrait =
            c.maxWidth < 390 &&
            MediaQuery.of(context).orientation == Orientation.portrait;
        final narrow = c.maxWidth < 380;
        final tight = c.maxWidth < 340;
        final filledStyle = _compactRideCardFilledStyle(cardActionStyle);
        final outlineStyle = _compactRideCardOutlinedStyle(
          cardOutlineStyle ?? _ghostButtonStyle(),
        );
        final statusText = _rideStatusLabel(
          (_effectiveStatusFor(b) ?? 'PENDING'),
        );
        final referenceChipText =
            '${cardReference.label}: ${cardReference.value}';
        final bagLabel = _tr(
          nl: '${b.bags ?? 0} bagage',
          en: '${b.bags ?? 0} bags',
          fr: '${b.bags ?? 0} bagages',
          es: '${b.bags ?? 0} equipaje',
        );
        final goToRideLabel = _tr(
          nl: 'Ga naar rit',
          en: 'Open ride',
          fr: 'Aller à la course',
          es: 'Ir al viaje',
        );

        if (compactPortrait) {
          return Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
            decoration: BoxDecoration(
              gradient: isMiddayGold
                  ? _middayGoldSurfaceGradient()
                  : (isMidnightBlue
                        ? _midnightBlueSurfaceGradient()
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF151515), Color(0xFF0B0B0B)],
                          )),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isMiddayGold
                    ? _middayGoldBorderColor(0.36)
                    : (isMidnightBlue
                          ? _midnightBlueBorderColor(0.42)
                          : kFluxidiYellow.withOpacity(0.24)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.24),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _pill(
                  icon: Icons.schedule,
                  text: dt,
                  borderColor: isMidnightBlue
                      ? _midnightBlueBorderColor(0.50)
                      : const Color(0x55FFD36A),
                  textColor: isMidnightBlue
                      ? _midnightBlueTextPrimary()
                      : const Color(0xFFFFD98A),
                  compact: true,
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Column(
                        children: [
                          Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: cardAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 28,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.34),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          Icon(
                            Icons.flag_rounded,
                            size: 19,
                            color: cardPrimary.withOpacity(0.88),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.from ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.1,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            b.to ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cardPrimary.withOpacity(0.92),
                              fontSize: 15.0,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          if (customerName.trim().isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Text(
                              '${_tr(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente')}: $customerName',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cardMuted.withOpacity(0.92),
                                fontSize: 11.8,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (isOperationalLeg && isRoundtripParent)
                      _pill(
                        text: legLabel,
                        borderColor: const Color(0xFF52B6FF),
                        textColor: const Color(0xFF9DD8FF),
                        compact: true,
                      ),
                    _pill(
                      text: statusText,
                      borderColor: isMidnightBlue
                          ? _midnightBlueBorderColor(0.62)
                          : const Color(0xFFB07A2A),
                      textColor: isMidnightBlue
                          ? _midnightBlueAccent()
                          : const Color(0xFFE7B46A),
                      compact: true,
                    ),
                    _pill(
                      text: (b.tier ?? 'premium').toUpperCase(),
                      compact: true,
                    ),
                    _pill(text: '${b.pax ?? 0} pax', compact: true),
                    _pill(text: bagLabel, compact: true),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_driverDisplayPriceForBooking(b) != null)
                      _pill(
                        text: _fmtMoney(
                          _driverDisplayPriceForBooking(b)!,
                          b.currency ?? 'EUR',
                        ),
                        borderColor: isMidnightBlue
                            ? _midnightBlueBorderColor(0.50)
                            : const Color(0x55FFD36A),
                        textColor: isMidnightBlue
                            ? _midnightBlueTextPrimary()
                            : const Color(0xFFFFD98A),
                        compact: true,
                      ),
                    const Spacer(),
                    SizedBox(
                      height: 42,
                      width: 42,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: isMidnightBlue
                              ? _midnightBlueAccent().withOpacity(0.20)
                              : (isMiddayGold
                                    ? const Color(0x40E8C57E)
                                    : const Color(0x33FFD36A)),
                          foregroundColor: cardPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _goToRide(b),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                if (cardReference.value.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    isOperationalLeg &&
                            isRoundtripParent &&
                            parentBookingId.isNotEmpty
                        ? '$referenceChipText · ${_tr(nl: 'Parent', en: 'Parent', fr: 'Parent', es: 'Padre')}: ${_safeRefPreview(parentBookingId)}'
                        : referenceChipText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cardMuted.withOpacity(0.82),
                      fontSize: 10.8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _buildRideCardPrimaryActions(
                  b: b,
                  actionBusy: actionBusy,
                  goToRideLabel: goToRideLabel,
                  filledStyle: filledStyle,
                  outlineStyle: outlineStyle,
                  stackSecondaryActions: true,
                ),
              ],
            ),
          );
        }

        return Container(
          padding: EdgeInsets.fromLTRB(
            tight ? 11 : 12,
            tight ? 11 : 12,
            tight ? 11 : 12,
            18,
          ),
          decoration: BoxDecoration(
            gradient: isMiddayGold
                ? _middayGoldSurfaceGradient()
                : (isMidnightBlue
                      ? _midnightBlueSurfaceGradient()
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF151515), Color(0xFF0B0B0B)],
                        )),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMiddayGold
                  ? _middayGoldBorderColor(0.36)
                  : (isMidnightBlue
                        ? _midnightBlueBorderColor(0.42)
                        : kFluxidiYellow.withOpacity(0.24)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.24),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.035),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: cardAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 2,
                          height: narrow ? 28 : 32,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.30),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Icon(
                          Icons.flag_rounded,
                          size: 15,
                          color: cardPrimary.withOpacity(0.86),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.from ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            b.to ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cardPrimary.withOpacity(0.90),
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          if (customerName.trim().isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Text(
                              '${_tr(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente')}: $customerName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cardMuted.withOpacity(0.92),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _pill(
                          icon: Icons.schedule,
                          text: dt,
                          borderColor: isMidnightBlue
                              ? _midnightBlueBorderColor(0.50)
                              : const Color(0x55FFD36A),
                          textColor: isMidnightBlue
                              ? _midnightBlueTextPrimary()
                              : const Color(0xFFFFD98A),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 34,
                          width: 34,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: isMidnightBlue
                                  ? _midnightBlueAccent().withOpacity(0.20)
                                  : (isMiddayGold
                                        ? const Color(0x40E8C57E)
                                        : const Color(0x33FFD36A)),
                              foregroundColor: cardPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => _goToRide(b),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (isOperationalLeg && isRoundtripParent)
                    _pill(
                      text: legLabel,
                      borderColor: const Color(0xFF52B6FF),
                      textColor: const Color(0xFF9DD8FF),
                    ),
                  _pill(
                    text: statusText,
                    borderColor: isMidnightBlue
                        ? _midnightBlueBorderColor(0.62)
                        : const Color(0xFFB07A2A),
                    textColor: isMidnightBlue
                        ? _midnightBlueAccent()
                        : const Color(0xFFE7B46A),
                  ),
                  _pill(text: (b.tier ?? 'premium').toUpperCase()),
                  _pill(text: '${b.pax ?? 0} pax'),
                  _pill(text: bagLabel),
                  if (_driverDisplayPriceForBooking(b) != null)
                    _pill(
                      text: _fmtMoney(
                        _driverDisplayPriceForBooking(b)!,
                        b.currency ?? 'EUR',
                      ),
                    ),
                ],
              ),
              if (cardReference.value.trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  isOperationalLeg &&
                          isRoundtripParent &&
                          parentBookingId.isNotEmpty
                      ? '$referenceChipText · ${_tr(nl: 'Parent', en: 'Parent', fr: 'Parent', es: 'Padre')}: ${_safeRefPreview(parentBookingId)}'
                      : referenceChipText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cardMuted.withOpacity(0.84),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _buildRideCardPrimaryActions(
                b: b,
                actionBusy: actionBusy,
                goToRideLabel: goToRideLabel,
                filledStyle: filledStyle,
                outlineStyle: outlineStyle,
                stackSecondaryActions: narrow,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCockpitWidget() {
    // ✅ Minimal cockpit (driving only):
    // - Big ETA + KM remaining (countdown starts when we move)
    // - Bottom controls: NAV | START/STOP | WACHT/GA
    final eta = _etaText.isNotEmpty ? _etaText : '—';
    final km = _kmRemainingText.isNotEmpty ? _kmRemainingText : '—';

    final bool tripStarted = _activeTripId != null;
    final bool waiting = _isWaiting;
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    final cockpitGradient = isMiddayGold
        ? _middayGoldSurfaceGradient(soft: true)
        : (isMidnightBlue
              ? _midnightBlueSurfaceGradient(soft: true)
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B1733), Color(0xFF0A1328)],
                ));
    final cockpitBorder = isMiddayGold
        ? _middayGoldBorderColor(tripStarted ? 0.52 : 0.34)
        : (isMidnightBlue
              ? _midnightBlueBorderColor(tripStarted ? 0.56 : 0.36)
              : kGlow.withOpacity(tripStarted ? 0.50 : 0.22));
    final cockpitGlow = isMidnightBlue
        ? _midnightBlueAccent().withOpacity(tripStarted ? 0.18 : 0.10)
        : (isMiddayGold
              ? const Color(0x66E8C57E).withOpacity(tripStarted ? 0.22 : 0.12)
              : kGlow.withOpacity(tripStarted ? 0.18 : 0.10));

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                gradient: cockpitGradient,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: cockpitBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: cockpitGlow,
                    blurRadius: tripStarted ? 16 : 10,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // === Big numbers ===
                  Row(
                    children: [
                      Expanded(
                        child: _bigMetric(
                          label: 'ETA',
                          value: eta,
                          isMidnightBlue: isMidnightBlue,
                          isMiddayGold: isMiddayGold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _bigMetric(
                          label: 'KM',
                          value: km,
                          suffix: 'km',
                          isMidnightBlue: isMidnightBlue,
                          isMiddayGold: isMiddayGold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // === Controls ===
                  Row(
                    children: [
                      Expanded(
                        child: _cockpitButton(
                          label: 'NAV',
                          icon: Icons.navigation,
                          onTap: _openNavigation,
                          enabled: _routeCoords.isNotEmpty,
                          isMidnightBlue: isMidnightBlue,
                          isMiddayGold: isMiddayGold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _cockpitButton(
                          label: tripStarted ? 'STOP' : 'START',
                          icon: tripStarted
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                          onTap: () {
                            final b = _activeBooking;
                            if (!tripStarted) {
                              if (b == null) {
                                _toast('Kies eerst een rit in Ritten.');
                                return;
                              }
                              _startTrip(b);
                            } else {
                              _stopTrip();
                            }
                          },
                          emphasis: true,
                          enabled: (tripStarted || _activeBooking != null),
                          isMidnightBlue: isMidnightBlue,
                          isMiddayGold: isMiddayGold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _cockpitButton(
                          label: waiting ? 'GA' : 'WACHT',
                          icon: waiting ? Icons.play_arrow : Icons.pause,
                          onTap: () {
                            if (!tripStarted) {
                              _toast('Start eerst de rit.');
                              return;
                            }
                            if (waiting) {
                              _exitWaitMode();
                            } else {
                              _enterWaitMode();
                            }
                          },
                          enabled: tripStarted,
                          isMidnightBlue: isMidnightBlue,
                          isMiddayGold: isMiddayGold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectRideEstimatePanel() {
    final destination = (_directRideDestinationText ?? '').trim();
    final showEstimate =
        _directRideDraft && _activeBooking == null && destination.isNotEmpty;
    final label = _tr(
      nl: 'Geschatte ritprijs',
      en: 'Estimated fare',
      fr: 'Prix estimé',
      es: 'Precio estimado',
    );
    final note = _tr(
      nl: 'Incl. btw • Definitieve prijs bij STOP',
      en: 'Incl. VAT • Final price at STOP',
      fr: 'TVA incl. • Prix final à l’arrêt',
      es: 'IVA incl. • Precio final al finalizar',
    );
    final loadingText = _tr(
      nl: 'Prijs berekenen…',
      en: 'Calculating fare…',
      fr: 'Calcul du prix…',
      es: 'Calculando precio…',
    );
    final unavailableText = _tr(
      nl: 'Schatting niet beschikbaar. De ritmeter blijft werken.',
      en: 'Estimate unavailable. The live meter still works.',
      fr: 'Estimation indisponible. Le taximètre reste actif.',
      es: 'Estimación no disponible. El taxímetro sigue funcionando.',
    );
    return DirectRideEstimatePanel(
      themeListenable: _activeDriverThemeListenable,
      visible: showEstimate,
      estimatedFare: _directRideEstimatedFare,
      isLoading: _directRideEstimateLoading,
      error: _directRideEstimateError,
      currency: _directRideEstimateCurrency,
      label: label,
      note: note,
      loadingText: loadingText,
      unavailableText: unavailableText,
      formatAmount: _formatDirectRideEstimateText,
    );
  }

  Widget _bigMetric({
    required String label,
    required String value,
    String? suffix,
    required bool isMidnightBlue,
    required bool isMiddayGold,
  }) {
    final fill = isMidnightBlue
        ? const Color(0xCC0B1B33)
        : (isMiddayGold
              ? const Color(0xCC2C2113)
              : Colors.white.withOpacity(0.06));
    final titleColor = isMidnightBlue
        ? _midnightBlueTextMuted()
        : (isMiddayGold
              ? _middayGoldTextMuted()
              : Colors.white.withOpacity(0.70));
    final valueColor = isMidnightBlue
        ? _midnightBlueTextPrimary()
        : (isMiddayGold ? _middayGoldTextPrimary() : Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: fill,
        border: Border.all(
          color: isMidnightBlue
              ? _midnightBlueBorderColor(0.34)
              : (isMiddayGold
                    ? _middayGoldBorderColor(0.30)
                    : Colors.white.withOpacity(0.10)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: titleColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    suffix,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _cockpitButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
    bool emphasis = false,
    required bool isMidnightBlue,
    required bool isMiddayGold,
  }) {
    final accent = isMidnightBlue
        ? _midnightBlueAccent()
        : (isMiddayGold ? const Color(0xFFE8C57E) : kGlow);
    final baseOpacity = enabled ? 1.0 : 0.45;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isMidnightBlue
              ? const Color(0xCC0B1B33).withOpacity(emphasis ? 1.0 : 0.88)
              : (isMiddayGold
                    ? const Color(0xCC2C2113).withOpacity(emphasis ? 1.0 : 0.88)
                    : Colors.white.withOpacity(emphasis ? 0.10 : 0.06)),
          border: Border.all(
            color: accent.withOpacity(
              emphasis ? 0.55 * baseOpacity : 0.28 * baseOpacity,
            ),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: (isMidnightBlue || isMiddayGold)
                  ? (emphasis
                        ? accent.withOpacity(baseOpacity)
                        : (isMidnightBlue
                              ? _midnightBlueTextPrimary().withOpacity(
                                  baseOpacity,
                                )
                              : _middayGoldTextPrimary().withOpacity(
                                  baseOpacity,
                                )))
                  : Colors.white.withOpacity(baseOpacity),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: (isMidnightBlue || isMiddayGold)
                    ? (emphasis
                          ? accent.withOpacity(baseOpacity)
                          : (isMidnightBlue
                                ? _midnightBlueTextPrimary().withOpacity(
                                    baseOpacity,
                                  )
                                : _middayGoldTextPrimary().withOpacity(
                                    baseOpacity,
                                  )))
                    : Colors.white.withOpacity(baseOpacity),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialGauge({
    required String label,
    required String value,
    required IconData icon,
    required bool highlight,
  }) {
    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, _) {
        final t = highlight ? (0.55 + 0.45 * _activePulse.value) : 0.0;

        return Container(
          height: 86,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: const Color(0xFF0B1733).withOpacity(0.55),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.20 + 0.18 * t),
              width: 1.0,
            ),
            boxShadow: [
              if (highlight)
                BoxShadow(
                  color: const Color(0x66F5C400).withOpacity(0.10 * t),
                  blurRadius: 22 * t,
                  spreadRadius: 1 * t,
                ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Round dial
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.18),
                    border: Border.all(
                      color: const Color(
                        0xFFFFD36A,
                      ).withOpacity(0.22 + 0.22 * t),
                      width: 1.0,
                    ),
                    boxShadow: [
                      if (highlight)
                        BoxShadow(
                          color: const Color(0x66F5C400).withOpacity(0.18 * t),
                          blurRadius: 18 * t,
                          spreadRadius: 1 * t,
                        ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: const Color(0xFFFFD36A).withOpacity(0.92),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Label (right side)
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dialAction({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedBuilder(
        animation: _activePulse,
        builder: (context, _) {
          final t = (0.65 + 0.35 * _activePulse.value);
          return Container(
            height: 86,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: filled
                  ? const Color(0xFF3B2230)
                  : const Color(0xFF0B1733).withOpacity(0.45),
              border: Border.all(
                color: filled
                    ? const Color(0xFFFFA7C0).withOpacity(0.50 + 0.25 * t)
                    : const Color(0xFFFFD36A).withOpacity(0.26 + 0.14 * t),
                width: 1.2,
              ),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: const Color(0x66FFA7C0).withOpacity(0.16 * t),
                        blurRadius: 18 * t,
                        spreadRadius: 1 * t,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: const Color(0x66F5C400).withOpacity(0.10 * t),
                        blurRadius: 18 * t,
                        spreadRadius: 1 * t,
                      ),
                    ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: filled
                      ? const Color(0xFFFFA7C0)
                      : const Color(0xFFFFD36A),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cockpitGauge({
    required String label,
    required String value,
    required IconData icon,
    required bool highlight,
  }) {
    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, child) {
        final t = highlight ? (0.55 + 0.45 * _activePulse.value) : 0.0;
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF0B1733).withOpacity(0.65),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.22 + 0.18 * t),
              width: 1.0,
            ),
            boxShadow: [
              if (highlight)
                BoxShadow(
                  color: const Color(0xFFFFD36A).withOpacity(0.10 * t),
                  blurRadius: 18 * t,
                  spreadRadius: 1 * t,
                ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: const Color(0xFFFFD36A).withOpacity(0.9),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _cockpitAction({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: filled
              ? const Color(0xFF3B2230)
              : const Color(0xFF0B1733).withOpacity(0.55),
          border: Border.all(
            color: filled
                ? const Color(0xFFFFA7C0).withOpacity(0.55)
                : const Color(0xFFFFD36A).withOpacity(0.28),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: filled ? const Color(0xFFFFA7C0) : const Color(0xFFFFD36A),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tinyStat(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$k: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.70),
              fontSize: 12,
            ),
          ),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildActiveDetailsSheet() {
    final b = _activeBooking;

    return DraggableScrollableSheet(
      // ✅ smaller collapsed size so it doesn't hide the values
      initialChildSize: 0.10,
      minChildSize: 0.10,
      // ✅ lower max so it doesn't dominate
      maxChildSize: 0.56,
      builder: (context, controller) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141B2F).withOpacity(0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(blurRadius: 18, spreadRadius: 2, color: Colors.black54),
            ],
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              top: 10,
              bottom: 18 + MediaQuery.of(context).padding.bottom + 50,
            ),
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                kActiveRideTitle,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (b != null) ...[
                _line(
                  icon: Icons.confirmation_number,
                  title: 'Trip ID',
                  value: _activeTripId ?? '—',
                  maxLines: 1,
                ),
                const SizedBox(height: 8),
                _line(
                  icon: Icons.radio_button_checked,
                  title: kPickupLabel,
                  value: b.from ?? '—',
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                _line(
                  icon: Icons.place,
                  title: kDropoffLabel,
                  value: b.to ?? '—',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(text: (b.tier ?? 'premium').toUpperCase()),
                    _pill(text: '${b.pax ?? 0} pax'),
                    _pill(text: '${b.bags ?? 0} bags'),
                    _pill(
                      text: 'Pings: $_pingCount',
                      textColor: Colors.white70,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFED6A5A).withOpacity(0.30),
                    foregroundColor: const Color(0xFFFFB4AA),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _stopTrip,
                  child: const Text(
                    'Stop rit',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill({
    IconData? icon,
    required String text,
    Color? borderColor,
    Color? textColor,
    bool compact = false,
  }) {
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    final defaultFill = isMiddayGold
        ? const Color(0xFF21170D)
        : (isMidnightBlue ? const Color(0xFF0A172B) : const Color(0xFF111111));
    final defaultBorder = isMiddayGold
        ? _middayGoldBorderColor(0.34)
        : (isMidnightBlue
              ? _midnightBlueBorderColor(0.38)
              : Colors.white.withOpacity(0.18));
    final defaultText = isMiddayGold
        ? _middayGoldTextPrimary()
        : (isMidnightBlue ? _midnightBlueTextPrimary() : Colors.white);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: defaultFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? defaultBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: compact ? 14 : 16,
              color: (textColor ?? defaultText.withOpacity(0.82)),
            ),
            SizedBox(width: compact ? 4 : 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: textColor ?? defaultText,
              fontSize: compact ? 12.2 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ridesSegmentChip({
    required String label,
    bool active = false,
    VoidCallback? onTap,
  }) {
    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;
    final activeFill = isMiddayGold
        ? const Color(0xFF3A2A15)
        : (isMidnightBlue ? const Color(0xFF0F2747) : const Color(0xFF17120A));
    final idleFill = isMiddayGold
        ? const Color(0xFF23190D)
        : (isMidnightBlue ? const Color(0xFF0A1A31) : const Color(0xFF111214));
    final activeBorder = isMiddayGold
        ? _middayGoldBorderColor(0.68)
        : (isMidnightBlue
              ? _midnightBlueBorderColor(0.72)
              : kFluxidiYellow.withOpacity(0.68));
    final idleBorder = isMiddayGold
        ? _middayGoldBorderColor(0.34)
        : (isMidnightBlue
              ? _midnightBlueBorderColor(0.36)
              : Colors.white.withOpacity(0.14));
    final activeText = isMiddayGold
        ? _middayGoldTextPrimary()
        : (isMidnightBlue ? _midnightBlueTextPrimary() : kFluxidiYellow);
    final idleText = isMiddayGold
        ? _middayGoldTextMuted()
        : (isMidnightBlue
              ? _midnightBlueTextMuted()
              : Colors.white.withOpacity(0.78));
    final chip = Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? activeFill : idleFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? activeBorder : idleBorder),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: TextStyle(
          color: active ? activeText.withOpacity(0.98) : idleText,
          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
          fontSize: 11.9,
        ),
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: chip,
    );
  }

  Widget _line({
    required IconData icon,
    required String title,
    required String value,
    int maxLines = 2,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                // ✅ FIX: w650 doesn't exist -> w600
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatPickup(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  bool _canAccessDriverOpsScreens() {
    final role = appRoleNotifier.value;
    return role == AppRole.driver ||
        role == AppRole.dispatcher ||
        role == AppRole.companyAdmin;
  }

  bool _canAccessCustomerBookingScreens() {
    final role = appRoleNotifier.value;
    return role == AppRole.customer ||
        role == AppRole.driver ||
        role == AppRole.companyAdmin;
  }

  bool _canAccessAdminManagementScreens() {
    return appRoleNotifier.value == AppRole.companyAdmin;
  }

  void _denyRoleAccess() {
    _toast('Geen toegang voor jouw rol.');
  }

  void _openBookingsHub() async {
    if (!_canAccessDriverOpsScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    // Close drawer first for a clean transition.
    Navigator.pop(context);
    debugPrint(
      '[DRIVER_RIDES][OPEN_SEGMENT] segment=${_DriverRidesHubSegment.available} source=drawer',
    );
    if (mounted) {
      setState(() {
        _bookingsHubVisible = true;
        _ridesHubSegment = _DriverRidesHubSegment.available;
      });
    } else {
      _bookingsHubVisible = true;
      _ridesHubSegment = _DriverRidesHubSegment.available;
    }
    _startBookingPolling(reason: 'bookings_hub_open');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _BookingsHubPage(
          title: kBookingsTitle,
          buildList: (h) => _buildBookingsList(h),
          onRefresh: () =>
              _refreshBookings(force: true, trigger: 'list_manual'),
          repaintListenable: _bookingsUiVersion,
          themeListenable: _activeDriverThemeListenable,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _bookingsHubVisible = false);
    _startBookingPolling(reason: 'bookings_hub_closed');
  }

  void _openBookingsHubFromDashboard({
    _DriverRidesHubSegment initialSegment = _DriverRidesHubSegment.available,
  }) async {
    if (!_canAccessDriverOpsScreens()) {
      _denyRoleAccess();
      return;
    }
    debugPrint(
      '[DRIVER_RIDES][OPEN_SEGMENT] segment=$initialSegment source=dashboard',
    );
    if (mounted) {
      setState(() {
        _bookingsHubVisible = true;
        _ridesHubSegment = initialSegment;
      });
    } else {
      _bookingsHubVisible = true;
      _ridesHubSegment = initialSegment;
    }
    if (initialSegment == _DriverRidesHubSegment.myRides) {
      _maybeForceRefreshOnMyRidesOpen(source: 'dashboard_tile');
    }
    _startBookingPolling(reason: 'bookings_hub_open');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _BookingsHubPage(
          title: kBookingsTitle,
          buildList: (h) => _buildBookingsList(h),
          onRefresh: () =>
              _refreshBookings(force: true, trigger: 'list_manual'),
          repaintListenable: _bookingsUiVersion,
          themeListenable: _activeDriverThemeListenable,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _bookingsHubVisible = false);
    _startBookingPolling(reason: 'bookings_hub_closed');
  }

  void _openLiveRide() async {
    if (!_canAccessDriverOpsScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    // Close drawer first for a clean transition.
    Navigator.pop(context);

    if (!_liveRideActive) {
      _toast('Geen actieve rit. Start een rit vanuit Ritten.');
      return;
    }

    // Bring driver focus back to the cockpit/map.
    try {
      setState(() {
        _cameraMode = _CameraMode.follow;
        _followCar = true;
        _hasSwitchedToFollow = true;
        _allowOverviewCamera = false;
      });
      await _applyMapStyleForMode();
      await _forceFollowCameraNow(caller: 'open_live_ride');
    } catch (_) {
      // Never crash the UI from a camera move.
    }
  }

  void _openTripHistory() {
    if (!_canAccessDriverOpsScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    Navigator.pop(context);
    _openTripHistoryFromDashboard();
  }

  void _openOfflineMaps() {
    if (!_canAccessDriverOpsScreens()) {
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.pop(context);
      }
      _denyRoleAccess();
      return;
    }
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
    if (_routeCoords.length >= 2 && kUseNavigationWorker) {
      unawaited(
        _maybeFetchOfflineCorridorMetadata(
          force: _hasOfflineCorridorNavContext(),
        ),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverOfflineMapsPage(
          themeListenable: _activeDriverThemeListenable,
          routeCorridorMetadata: _lastOfflineCorridorMetadata,
        ),
      ),
    );
  }

  Future<void> _openTripHistoryFromDashboard() async {
    if (!_canAccessDriverOpsScreens()) {
      _denyRoleAccess();
      return;
    }
    final bookingDetailsById = <String, Map<String, dynamic>>{};
    for (final booking in _bookings) {
      final bookingId = booking.bookingId.trim();
      if (bookingId.isEmpty) continue;
      final details = Map<String, dynamic>.from(booking.details);
      details['booking_id'] = bookingId;
      details['bookingId'] = bookingId;
      final nestedBooking = details['booking'] is Map
          ? Map<String, dynamic>.from(details['booking'] as Map)
          : <String, dynamic>{};
      nestedBooking['booking_id'] = bookingId;
      nestedBooking['bookingId'] = bookingId;
      details['booking'] = nestedBooking;
      bookingDetailsById[bookingId] = details;
    }
    final activeBookingId = _activeBooking?.bookingId.trim() ?? '';
    if (activeBookingId.isNotEmpty) {
      final activeDetails = Map<String, dynamic>.from(_activeBooking!.details);
      activeDetails['booking_id'] = activeBookingId;
      activeDetails['bookingId'] = activeBookingId;
      final nestedBooking = activeDetails['booking'] is Map
          ? Map<String, dynamic>.from(activeDetails['booking'] as Map)
          : <String, dynamic>{};
      nestedBooking['booking_id'] = activeBookingId;
      nestedBooking['bookingId'] = activeBookingId;
      activeDetails['booking'] = nestedBooking;
      bookingDetailsById[activeBookingId] = activeDetails;
    }
    final strictScope = _strictDriverHistoryScopeIdsWithSource();
    if (strictScope == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Bedrijfscontext ontbreekt. Ritgeschiedenis kan niet veilig geladen worden.',
              en: 'Company context is missing. Trip history cannot be loaded safely.',
              fr: 'Le contexte entreprise est manquant. L’historique des trajets ne peut pas être chargé en toute sécurité.',
              es: 'Falta el contexto de empresa. El historial de viajes no puede cargarse de forma segura.',
            ),
          ),
        ),
      );
      return;
    }
    final historyDriverId = kDriverId.trim();
    final historyHeaders = await _tripsHistoryAuthHeaders(
      scopeSource: strictScope.source,
      driverId: historyDriverId,
      fetchContext: 'trip_history_page',
    );
    if (!mounted) return;
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (ctx) => _TripHistoryPage(
                workerBaseUrl: kWorkerBaseUrl,
                tenantId: strictScope.tenantId,
                companyId: strictScope.companyId,
                driverId: historyDriverId,
                headers: historyHeaders,
                bookingDetailsById: bookingDetailsById,
                driverThemeListenable: _activeDriverThemeListenable,
              ),
            ),
          )
          .then((_) {
            if (!mounted) return;
            unawaited(
              _refreshCompletedTodayCount(reason: 'trip_history_return'),
            );
          }),
    );
  }

  Future<void> _openCalculatorFromDashboard() async {
    if (!_canAccessCustomerBookingScreens()) {
      _denyRoleAccess();
      return;
    }
    final isBusinessPreview = _isBusinessPreviewMode;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
          persistToCustomerBookings: false,
          entryContext: isBusinessPreview
              ? BookingEntryContext.companyAdmin
              : BookingEntryContext.driver,
          driverThemeListenable: _activeDriverThemeListenable,
          useDriverVisualTheme: true,
          previewAssignedDriverId: isBusinessPreview
              ? _effectiveActiveDriverIdForRideScope()
              : null,
          previewAssignedVehicleId: isBusinessPreview
              ? _effectiveActiveVehicleIdForRideScope()
              : null,
        ),
      ),
    );
    if (created == true && mounted) {
      await _refreshBookings(force: true, trigger: 'calculator_created');
    }
  }

  Future<void> _openCalculator() async {
    if (!_canAccessCustomerBookingScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    // Close drawer first for a clean transition.
    Navigator.pop(context);

    final isBusinessPreview = _isBusinessPreviewMode;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
          persistToCustomerBookings: false,
          entryContext: isBusinessPreview
              ? BookingEntryContext.companyAdmin
              : BookingEntryContext.driver,
          driverThemeListenable: _activeDriverThemeListenable,
          useDriverVisualTheme: true,
          previewAssignedDriverId: isBusinessPreview
              ? _effectiveActiveDriverIdForRideScope()
              : null,
          previewAssignedVehicleId: isBusinessPreview
              ? _effectiveActiveVehicleIdForRideScope()
              : null,
        ),
      ),
    );
    if (created == true && mounted) {
      await _refreshBookings(force: true, trigger: 'calculator_created');
    }
  }

  void _openBusinessSettings() {
    if (!_canAccessAdminManagementScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    Navigator.pop(context);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (ctx) => const BusinessSettingsPage()));
  }

  void _openVehicles() {
    if (!_canAccessAdminManagementScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    Navigator.pop(context);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (ctx) => const VehicleManagementPage()));
  }

  Drawer _buildDrawer() {
    final role = appRoleNotifier.value;
    final isCustomer = role == AppRole.customer;
    final isDriver = role == AppRole.driver;
    final isCompanyAdmin = role == AppRole.companyAdmin;
    final isDispatcher = role == AppRole.dispatcher;
    final canSeeDriverOps = isDriver || isDispatcher || isCompanyAdmin;
    final canSeeAdminManagement = isCompanyAdmin;
    final canSeeCustomerBooking = isCustomer || isDriver || isCompanyAdmin;

    final isMidnightBlue =
        driverThemeNotifier.value == DriverThemeVariant.midnightBlue;
    final isMiddayGold =
        driverThemeNotifier.value == DriverThemeVariant.highContrast;

    final drawerBg = isMidnightBlue
        ? const Color(0xFF020711)
        : (isMiddayGold ? const Color(0xFF100B06) : const Color(0xFF050505));
    final drawerGradient = isMidnightBlue
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF020711), Color(0xFF07111F), Color(0xFF0B1B33)],
          )
        : (isMiddayGold
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF100B06),
                    Color(0xFF17110A),
                    Color(0xFF2C2113),
                  ],
                )
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF050505), Color(0xFF101010)],
                ));
    final cardBg = isMidnightBlue
        ? const Color(0xFF07111F)
        : (isMiddayGold ? const Color(0xFF17110A) : const Color(0xFF101010));
    final rowBg = isMidnightBlue
        ? const Color(0xFF0B1B33)
        : (isMiddayGold ? const Color(0xFF2C2113) : const Color(0xFF121212));
    final sidebarAccent = isMidnightBlue
        ? const Color(0xFF4DA3FF)
        : (isMiddayGold ? const Color(0xFFFFDFA3) : const Color(0xFFE5B641));
    final sidebarAccentSoft = isMidnightBlue
        ? const Color(0xFF4DA3FF).withOpacity(0.50)
        : (isMiddayGold
              ? const Color(0xFFE8C57E).withOpacity(0.52)
              : const Color(0x33E5B641));
    final sidebarTextPrimary = isMidnightBlue
        ? const Color(0xFFEAF6FF)
        : (isMiddayGold ? const Color(0xFFFFF0D0) : Colors.white);
    final sidebarTextMuted = isMidnightBlue
        ? const Color(0xFFAFCBEA)
        : (isMiddayGold
              ? const Color(0xFFE1CCA0)
              : Colors.white.withOpacity(0.83));
    final divider = isMidnightBlue
        ? const Color(0xFF4DA3FF).withOpacity(0.32)
        : (isMiddayGold
              ? const Color(0xFFE8C57E).withOpacity(0.34)
              : const Color(0x33E5B641));

    InputDecoration compactSelectDecoration() => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: rowBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: sidebarAccentSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: sidebarAccentSoft),
      ),
    );

    Widget controlLabel(String text) => Text(
      text,
      style: TextStyle(
        color: sidebarTextMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );

    final screenWidth = MediaQuery.of(context).size.width;
    final railWidth = screenWidth < 380
        ? 94.0
        : (screenWidth < 700 ? 110.0 : 126.0);

    Widget cockpitRailButton({
      required IconData icon,
      required String semanticLabel,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Tooltip(
          message: semanticLabel,
          child: Semantics(
            button: true,
            label: semanticLabel,
            child: Material(
              color: rowBg,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: onTap,
                child: Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: sidebarAccentSoft),
                  ),
                  child: Icon(icon, size: 24, color: sidebarAccent),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget miniAction({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Tooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: sidebarAccent,
                  backgroundColor: cardBg,
                  side: BorderSide(
                    color: sidebarAccent.withOpacity(0.66),
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Drawer(
      width: railWidth + 20,
      backgroundColor: drawerBg,
      child: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: drawerGradient),
          child: Center(
            child: SizedBox(
              width: railWidth,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                children: [
                  Text(
                    _tr(
                      nl: 'Cockpit',
                      en: 'Cockpit',
                      fr: 'Cockpit',
                      es: 'Cabina',
                    ),
                    style: TextStyle(
                      color: sidebarTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    'Fluxidi',
                    style: TextStyle(
                      color: sidebarAccent.withOpacity(0.92),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: sidebarAccent.withOpacity(0.24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        controlLabel(
                          _tr(
                            nl: 'Taal',
                            en: 'Language',
                            fr: 'Langue',
                            es: 'Idioma',
                          ),
                        ),
                        const SizedBox(height: 5),
                        DropdownButtonFormField<String>(
                          value: currentLanguageCode,
                          items: const [
                            DropdownMenuItem(value: 'nl', child: Text('NL')),
                            DropdownMenuItem(value: 'en', child: Text('EN')),
                            DropdownMenuItem(value: 'fr', child: Text('FR')),
                            DropdownMenuItem(value: 'es', child: Text('ES')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setAppLanguageByCode(v);
                            setState(() {});
                          },
                          dropdownColor: cardBg,
                          decoration: compactSelectDecoration(),
                          style: TextStyle(
                            color: sidebarTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          iconEnabledColor: sidebarAccent,
                        ),
                        const SizedBox(height: 9),
                        controlLabel(
                          _tr(nl: 'Kaart', en: 'Map', fr: 'Carte', es: 'Mapa'),
                        ),
                        const SizedBox(height: 5),
                        DropdownButtonFormField<MapThemeMode>(
                          value: _effectiveMapThemeFor(_cameraMode),
                          items: [
                            DropdownMenuItem(
                              value: MapThemeMode.light,
                              child: Text(
                                _tr(
                                  nl: 'Licht',
                                  en: 'Light',
                                  fr: 'Clair',
                                  es: 'Claro',
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: MapThemeMode.dark,
                              child: Text(
                                _tr(
                                  nl: 'Donker',
                                  en: 'Dark',
                                  fr: 'Sombre',
                                  es: 'Oscuro',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            _setMapTheme(v);
                          },
                          dropdownColor: cardBg,
                          decoration: compactSelectDecoration(),
                          style: TextStyle(
                            color: sidebarTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          iconEnabledColor: sidebarAccent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Divider(color: divider),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<ActiveDriverSession?>(
                    valueListenable: activeDriverSessionNotifier,
                    builder: (context, session, _) {
                      if (!(isDriver && session != null)) {
                        return const SizedBox.shrink();
                      }
                      final isBusinessPreviewSession =
                          widget.openedFromBusinessHome ||
                          (session.isCompanyAdminDriverViewSession);
                      if (isBusinessPreviewSession) {
                        debugPrint(
                          '[DRIVER_SESSION][CLEAR_BLOCKED] reason=business_preview_switch_action',
                        );
                      }
                      return Column(
                        children: [
                          cockpitRailButton(
                            icon: Icons.folder_copy_outlined,
                            semanticLabel: _tr(
                              nl: 'Documenten',
                              en: 'Documents',
                              fr: 'Documents',
                              es: 'Documentos',
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DriverMyDocumentsPage(
                                    themeListenable:
                                        _activeDriverThemeListenable,
                                  ),
                                ),
                              );
                            },
                          ),
                          if (!isBusinessPreviewSession)
                            cockpitRailButton(
                              icon: Icons.swap_horiz_rounded,
                              semanticLabel: _tr(
                                nl: 'Wissel',
                                en: 'Switch',
                                fr: 'Changer',
                                es: 'Cambiar',
                              ),
                              onTap: () async {
                                Navigator.pop(context);
                                await DriverSessionStore.instance.clear();
                                if (!context.mounted) return;
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (_) => const ChauffeurLoginPage(),
                                  ),
                                  (route) => false,
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                  if (canSeeDriverOps)
                    cockpitRailButton(
                      icon: Icons.list_alt_rounded,
                      semanticLabel: _tr(
                        nl: 'Ritten',
                        en: 'Rides',
                        fr: 'Courses',
                        es: 'Viajes',
                      ),
                      onTap: _openBookingsHub,
                    ),
                  if (canSeeDriverOps)
                    cockpitRailButton(
                      icon: Icons.local_taxi_outlined,
                      semanticLabel: _tr(
                        nl: 'Straatrit',
                        en: 'Street',
                        fr: 'Rue',
                        es: 'Calle',
                      ),
                      onTap: _openDirectRideEntry,
                    ),
                  if (canSeeDriverOps)
                    cockpitRailButton(
                      icon: Icons.history,
                      semanticLabel: _tr(
                        nl: 'Historiek',
                        en: 'History',
                        fr: 'Historique',
                        es: 'Historial',
                      ),
                      onTap: _openTripHistory,
                    ),
                  if (canSeeDriverOps)
                    cockpitRailButton(
                      icon: Icons.wifi_off_rounded,
                      semanticLabel: _tr(
                        nl: 'Offline kaarten',
                        en: 'Offline maps',
                        fr: 'Cartes hors ligne',
                        es: 'Mapas sin conexión',
                      ),
                      onTap: _openOfflineMaps,
                    ),
                  if (canSeeCustomerBooking)
                    cockpitRailButton(
                      icon: Icons.calculate_outlined,
                      semanticLabel: _tr(
                        nl: 'Prijs',
                        en: 'Price',
                        fr: 'Prix',
                        es: 'Precio',
                      ),
                      onTap: _openCalculator,
                    ),
                  if (canSeeAdminManagement)
                    cockpitRailButton(
                      icon: Icons.business_center_outlined,
                      semanticLabel: _tr(
                        nl: 'Bedrijf',
                        en: 'Business',
                        fr: 'Entreprise',
                        es: 'Empresa',
                      ),
                      onTap: _openBusinessSettings,
                    ),
                  if (canSeeAdminManagement)
                    cockpitRailButton(
                      icon: Icons.directions_car_filled_outlined,
                      semanticLabel: _tr(
                        nl: 'Voertuigen',
                        en: 'Vehicles',
                        fr: 'Vehicules',
                        es: 'Vehiculos',
                      ),
                      onTap: _openVehicles,
                    ),
                  const SizedBox(height: 2),
                  Divider(color: divider),
                  const SizedBox(height: 6),
                  if (canSeeDriverOps)
                    cockpitRailButton(
                      icon: Icons.refresh_rounded,
                      semanticLabel: _tr(
                        nl: 'Vernieuw',
                        en: 'Refresh',
                        fr: 'Actualiser',
                        es: 'Actualizar',
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _refreshBookings(force: true, trigger: 'drawer_manual');
                      },
                    ),
                  if (canSeeDriverOps)
                    cockpitRailButton(
                      icon: Icons.my_location_rounded,
                      semanticLabel: _tr(
                        nl: 'Centreer',
                        en: 'Center',
                        fr: 'Centrer',
                        es: 'Centrar',
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        await _centerOnMe();
                      },
                    ),
                  if (canSeeDriverOps) const SizedBox(height: 6),
                  if (canSeeDriverOps)
                    Column(
                      children: [
                        miniAction(
                          icon: Icons.home_outlined,
                          label: _tr(
                            nl: 'Start',
                            en: 'Start',
                            fr: 'Accueil',
                            es: 'Inicio',
                          ),
                          onTap: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const RoleEntryPage(),
                              ),
                              (route) => false,
                            );
                          },
                        ),
                        miniAction(
                          icon: Icons.badge_outlined,
                          label: _tr(
                            nl: 'Chauffeur',
                            en: 'Driver',
                            fr: 'Chauffeur',
                            es: 'Conductor',
                          ),
                          onTap: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => DriverHomePage(
                                  openedFromBusinessHome:
                                      widget.openedFromBusinessHome,
                                ),
                              ),
                              (route) => false,
                            );
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small icon button with Fluxidi yellow glow.
///
/// Used in the brand bar (menu icon, etc.). Keeps hit-area large for in-car use.
