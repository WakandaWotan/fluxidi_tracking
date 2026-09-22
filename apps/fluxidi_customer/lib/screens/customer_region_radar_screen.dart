import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/business/regional_demand_consistency.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/navigation/mapbox_platform_surface.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../app/customer_app_config.dart';
import '../app/customer_labels.dart';
import '../bridge/customer_runtime.dart';
import '../region_radar/region_interest_client.dart';
import '../region_radar/region_radar_geocode.dart';
import '../region_radar/region_radar_map_interest.dart';
import '../region_radar/region_radar_own_interest_store.dart';

/// Customer-app Region Radar, aligned with the website view.
class CustomerRegionRadarScreen extends StatefulWidget {
  const CustomerRegionRadarScreen({
    super.key,
    this.config = kCustomerAppConfig,
    this.client,
    this.placeLookup,
    this.mapBuilder,
    this.profileLoader,
    this.ownInterestStore,
    this.onRegionMoved,
  });

  final CustomerAppConfig config;
  final RegionInterestClient? client;
  final RegionRadarPlaceLookup? placeLookup;
  final Future<CustomerProfile?> Function()? profileLoader;
  final RegionRadarOwnInterestStore? ownInterestStore;
  final void Function(double lat, double lon)? onRegionMoved;

  /// Tests replace the native map. Production keeps the real Mapbox map.
  final WidgetBuilder? mapBuilder;

  @override
  State<CustomerRegionRadarScreen> createState() =>
      _CustomerRegionRadarScreenState();
}

class _CustomerRegionRadarScreenState extends State<CustomerRegionRadarScreen> {
  final TextEditingController _postcodeCtrl = TextEditingController();
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  late final RegionInterestClient _client;
  late final RegionRadarOwnInterestStore _ownStore;

  String _country = 'BE';
  bool _lookingUp = false;
  bool _submitting = false;
  bool _submitted = false;
  bool _ownInThisRegion = false;
  bool _pulseOwn = false;
  String? _lookupError;
  String? _formError;
  String? _formSuccess;
  RegionRadarSnapshot? _snapshot;
  RegionRadarPlace? _place;
  int _lookupGeneration = 0;
  mb.MapboxMap? _map;
  Timer? _pulseTimer;
  int _projectGeneration = 0;

  double _mapZoom = 9.8;
  Map<String, Offset> _markerPixels = const <String, Offset>{};

  List<RegionRadarMapMarker> get _markers => clusterRegionRadarMarkers(
    markers: regionRadarMapMarkers(
      place: _place,
      snapshot: _snapshot,
      ownInThisRegion: _ownInThisRegion,
    ),
    zoom: _mapZoom,
  );

  @override
  void initState() {
    super.initState();
    _client =
        widget.client ??
        RegionInterestClient(baseUrl: widget.config.publicBookingBaseUrl);
    _ownStore = widget.ownInterestStore ?? RegionRadarOwnInterestStore();
    _postcodeCtrl.addListener(_onRegionFieldsChanged);
    unawaited(_prefillFromProfile());
    unawaited(_ownStore.ensureLoaded());
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _postcodeCtrl.removeListener(_onRegionFieldsChanged);
    _postcodeCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillFromProfile() async {
    final profile = await (widget.profileLoader ?? loadLocalCustomerProfile)();
    if (!mounted || profile == null) return;
    final parts = profile.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    setState(() {
      if (_firstNameCtrl.text.isEmpty && parts.isNotEmpty) {
        _firstNameCtrl.text = parts.first;
        _lastNameCtrl.text = parts.length > 1 ? parts.skip(1).join(' ') : '';
      }
      if (_emailCtrl.text.isEmpty) _emailCtrl.text = profile.email;
      if (_phoneCtrl.text.isEmpty) _phoneCtrl.text = profile.phone;
      if (_postcodeCtrl.text.isEmpty &&
          profile.preferredPostcode.trim().isNotEmpty) {
        _postcodeCtrl.text = profile.preferredPostcode.trim().toUpperCase();
      }
      final billing = parseDemandRadarCountryCode(profile.billingCountry);
      if (billing.isNotEmpty) _country = billing;
    });
  }

  void _onRegionFieldsChanged() {
    if (_place == null && _snapshot == null) return;
    final current = normalizeDemandRadarPostcode(_postcodeCtrl.text);
    if (_place != null && current == _place!.postcode) return;
    setState(() {
      _place = null;
      _snapshot = null;
      _ownInThisRegion = false;
      _pulseOwn = false;
    });
  }

  void _selectCountry(String next) {
    setState(() {
      _country = next;
      if (_place != null && _place!.country != next) {
        _place = null;
        _snapshot = null;
        _ownInThisRegion = false;
        _pulseOwn = false;
      }
    });
  }

  RegionInterestDraft _draft() {
    return RegionInterestDraft(
      country: _place?.country ?? _country,
      postcode: _place?.postcode ?? _postcodeCtrl.text,
      firstName: _firstNameCtrl.text,
      lastName: _lastNameCtrl.text,
      email: _emailCtrl.text,
      phone: _phoneCtrl.text,
      locale: currentLanguageCode,
    );
  }

  Future<void> _viewRegion() async {
    final country = parseDemandRadarCountryCode(_country);
    final postcode = normalizeDemandRadarPostcode(_postcodeCtrl.text);
    if (country.isEmpty || postcode.isEmpty) {
      setState(() {
        _lookupError = CustomerText.radarNeedPostcode.current;
        _snapshot = null;
        _place = null;
      });
      return;
    }
    final generation = ++_lookupGeneration;
    setState(() {
      _lookingUp = true;
      _lookupError = null;
      _snapshot = null;
      _place = null;
    });
    try {
      final snapshotFuture = _client.fetchRadar(
        country: country,
        postcode: postcode,
      );
      final placeFuture = (widget.placeLookup ?? _defaultPlaceLookup)(
        country: country,
        postcode: postcode,
        language: currentLanguageCode,
      );
      final snapshot = await snapshotFuture;
      final place = await placeFuture;
      if (!mounted || generation != _lookupGeneration) return;
      if (place == null) {
        setState(() {
          _lookingUp = false;
          _snapshot = null;
          _place = null;
          _ownInThisRegion = false;
          _lookupError = CustomerText.radarPostcodeNotFound.current;
        });
        return;
      }
      final snapshotMatches =
          parseDemandRadarCountryCode(snapshot.country) == place.country &&
          normalizeDemandRadarPostcode(snapshot.postcode) == place.postcode;
      final ownHere = await _ownStore.contains(
        country: place.country,
        postcode: place.postcode,
      );
      if (!mounted || generation != _lookupGeneration) return;
      setState(() {
        _lookingUp = false;
        _place = place;
        _snapshot = snapshotMatches ? snapshot : null;
        _ownInThisRegion = ownHere;
        _lookupError = null;
      });
      widget.onRegionMoved?.call(place.lat, place.lon);
      await _moveMapToRegion();
      await _projectMarkers();
    } catch (_) {
      if (!mounted || generation != _lookupGeneration) return;
      setState(() {
        _lookingUp = false;
        _snapshot = null;
        _place = null;
        _ownInThisRegion = false;
        _lookupError = CustomerText.radarFail.current;
      });
    }
  }

  Future<RegionRadarPlace?> _defaultPlaceLookup({
    required String country,
    required String postcode,
    required String language,
  }) {
    return lookupRegionRadarPlace(
      token: widget.config.mapboxToken,
      country: country,
      postcode: postcode,
      language: language,
    );
  }

  Future<void> _revealSubmittedRegion({
    required RegionInterestDraft draft,
    required RegionRadarSnapshot? snapshot,
    required bool pulse,
  }) async {
    final generation = ++_lookupGeneration;
    try {
      final place = await (widget.placeLookup ?? _defaultPlaceLookup)(
        country: parseDemandRadarCountryCode(draft.country),
        postcode: normalizeDemandRadarPostcode(draft.postcode),
        language: currentLanguageCode,
      );
      if (!mounted || generation != _lookupGeneration || place == null) return;
      setState(() {
        _place = place;
        if (snapshot != null) _snapshot = snapshot;
        _ownInThisRegion = true;
        _lookupError = null;
      });
      widget.onRegionMoved?.call(place.lat, place.lon);
      if (pulse) _startOwnPulse();
      await _moveMapToRegion();
      await _projectMarkers();
    } catch (_) {}
  }

  Future<void> _onMapReady() async {
    await _moveMapToRegion();
    await _projectMarkers();
  }

  Future<void> _moveMapToRegion() async {
    final map = _map;
    final place = _place;
    if (map == null || place == null) return;
    await map.flyTo(
      mb.CameraOptions(
        center: mb.Point(coordinates: mb.Position(place.lon, place.lat)),
        zoom: 9.8,
      ),
      mb.MapAnimationOptions(duration: 700),
    );
  }

  void _startOwnPulse() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _pulseTimer?.cancel();
    setState(() => _pulseOwn = true);
    _pulseTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _pulseOwn = false);
    });
  }

  Future<void> _projectMarkers() async {
    final map = _map;
    final markers = _markers;
    if (map == null || markers.isEmpty) {
      if (_markerPixels.isNotEmpty && mounted) {
        setState(() => _markerPixels = const <String, Offset>{});
      }
      return;
    }
    final generation = ++_projectGeneration;
    try {
      final state = await map.getCameraState();
      final zoom = state.zoom;
      final pixels = <String, Offset>{};
      for (final marker in markers) {
        final screen = await map.pixelForCoordinate(
          mb.Point(coordinates: mb.Position(marker.lon, marker.lat)),
        );
        pixels[marker.id] = Offset(screen.x, screen.y);
      }
      if (!mounted || generation != _projectGeneration) return;
      setState(() {
        _mapZoom = zoom;
        _markerPixels = pixels;
      });
    } catch (_) {}
  }

  void _showMarkerInfo(RegionRadarMapMarker marker) {
    final placeLine = regionRadarPlaceLine(
      postcode: marker.postcode,
      placeName: marker.placeName,
    );
    final interested = regionRadarInterestedLabel(
      displayCount: marker.displayCount,
      interestedWord: CustomerText.radarInterested.current,
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                marker.kind == RegionRadarMarkerKind.ownInterest
                    ? CustomerText.radarYourInterest.current
                    : marker.kind == RegionRadarMarkerKind.selectedRegion
                    ? CustomerText.radarSelectedRegion.current
                    : placeLine,
                key: Key(
                  marker.kind == RegionRadarMarkerKind.ownInterest
                      ? 'customer_region_radar_own_info'
                      : marker.kind == RegionRadarMarkerKind.selectedRegion
                      ? 'customer_region_radar_selected_info'
                      : 'customer_region_radar_group_info',
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(placeLine),
              if (marker.kind == RegionRadarMarkerKind.regionGroup &&
                  marker.displayCount.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  interested,
                  key: const Key('customer_region_radar_group_count'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_submitting || _submitted) return;
    final draft = _draft();
    final error = regionInterestFieldError(
      draft: draft,
      translate: ({
        required String nl,
        required String en,
        required String fr,
        required String es,
        required String de,
      }) => CustomerLabel(nl: nl, en: en, fr: fr, es: es, de: de).current,
    );
    if (error != null) {
      setState(() {
        _formError = error;
        _formSuccess = null;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
      _formSuccess = null;
    });
    try {
      final result = await _client.submit(draft);
      if (!mounted) return;
      if (!result.ok) {
        setState(() {
          _submitting = false;
          _formError = CustomerText.radarSubmitFailed.current;
        });
        return;
      }
      await _ownStore.remember(
        country: draft.country,
        postcode: draft.postcode,
      );
      if (!mounted) return;
      final matchesPlace =
          _place != null &&
          parseDemandRadarCountryCode(_place!.country) ==
              parseDemandRadarCountryCode(draft.country) &&
          normalizeDemandRadarPostcode(_place!.postcode) ==
              normalizeDemandRadarPostcode(draft.postcode);
      setState(() {
        _submitting = false;
        _submitted = true;
        _ownInThisRegion = matchesPlace || _ownInThisRegion;
        _formSuccess = result.alreadyRegistered
            ? CustomerText.radarAlreadyRegistered.current
            : CustomerText.radarSaved.current;
        if (result.snapshot != null) _snapshot = result.snapshot;
      });
      if (matchesPlace) {
        if (!result.alreadyRegistered) _startOwnPulse();
        await _moveMapToRegion();
        await _projectMarkers();
      } else {
        await _revealSubmittedRegion(
          draft: draft,
          snapshot: result.snapshot,
          pulse: !result.alreadyRegistered,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = CustomerText.radarSubmitFailed.current;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<CustomerThemeVariant>(
          valueListenable: customerThemeNotifier,
          builder: (context, variant, _) {
        final palette = paletteForCustomerTheme(variant);
        return Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            backgroundColor: palette.background,
            foregroundColor: palette.textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(CustomerText.regionRadar.current),
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTablet = constraints.biggest.shortestSide >= 600;
                final isLandscape =
                    constraints.maxWidth > constraints.maxHeight;
                final sideBySide =
                    isTablet && isLandscape && constraints.maxWidth >= 980;
                final horizontal = isTablet ? 24.0 : 16.0;
                return SingleChildScrollView(
                  key: const Key('customer_region_radar_scroll'),
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    12,
                    horizontal,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _HeroIntro(palette: palette),
                      const SizedBox(height: 20),
                      if (sideBySide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: _mapBlock(palette, isTablet)),
                            const SizedBox(width: 16),
                            Expanded(child: _formBlock(palette)),
                          ],
                        )
                      else ...<Widget>[
                        _mapBlock(palette, isTablet),
                        const SizedBox(height: 16),
                        _formBlock(palette),
                      ],
                      const SizedBox(height: 24),
                      _Steps(palette: palette),
                    ],
                  ),
                );
              },
            ),
          ),
        );
          },
        );
      },
    );
  }

  Widget _mapBlock(CustomerThemePalette palette, bool isTablet) {
    return _Panel(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            CustomerText.radarSearchTitle.current,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            CustomerText.radarSearchHint.current,
            style: TextStyle(color: palette.textMuted, height: 1.35),
          ),
          const SizedBox(height: 14),
          _RegionControls(
            palette: palette,
            country: _country,
            postcode: _postcodeCtrl,
            lookingUp: _lookingUp,
            onCountry: _selectCountry,
            onView: _viewRegion,
            sideBySide: isTablet,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: isTablet ? 380 : 240,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const ColoredBox(color: Color(0xFFF4F6F8)),
                  widget.mapBuilder?.call(context) ??
                      mapboxSurfaceOrUnsupported(
                        unsupportedMessage:
                            CustomerText.radarMapMissing.current,
                        buildMap: () => mb.MapWidget(
                          key: const Key('customer_region_radar_map'),
                          textureView: true,
                          styleUri: mb.MapboxStyles.MAPBOX_STREETS,
                          cameraOptions: mb.CameraOptions(
                            center: mb.Point(
                              coordinates: mb.Position(4.3517, 50.8503),
                            ),
                            zoom: 6.4,
                          ),
                          onMapCreated: (map) {
                            _map = map;
                            unawaited(_onMapReady());
                          },
                          onMapIdleListener: (_) {
                            unawaited(_projectMarkers());
                          },
                        ),
                      ),
                  _RegionRadarOverlayMarkers(
                    markers: _markers,
                    pulseOwn: _pulseOwn,
                    pixels: _markerPixels,
                    onTap: _showMarkerInfo,
                  ),
                  if (_place == null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _MapBanner(
                        palette: palette,
                        title: _lookingUp
                            ? CustomerText.radarSearching.current
                            : CustomerText.radarMapIdle.current,
                      ),
                    ),
                  if (_place != null &&
                      _snapshot != null &&
                      _snapshot!.hasServerCount)
                    Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 56, 12),
                        child: _InterestBadge(
                          palette: palette,
                          snapshot: _snapshot!,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            CustomerText.radarMapCaption.current,
            key: const Key('customer_region_radar_map_caption'),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          if (_place != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _place!.label,
              key: const Key('customer_region_radar_place'),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_snapshot != null && _snapshot!.hasServerCount) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                regionRadarSummaryLine(
                  country: _place!.country,
                  postcode: _place!.postcode,
                  displayCount: _snapshot!.displayCount,
                  regionWord: CustomerText.radarRegionWord.current,
                  partnersWanted: CustomerText.radarPartnersWanted.current,
                ),
                key: const Key('customer_region_radar_region_line'),
                style: TextStyle(color: palette.textMuted, height: 1.35),
              ),
            ],
          ],
          if (_lookupError != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _lookupError!,
              key: const Key('customer_region_radar_lookup_error'),
              style: TextStyle(color: palette.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _formBlock(CustomerThemePalette palette) {
    return _Panel(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            CustomerText.radarFormTitle.current,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            CustomerText.radarFormHint.current,
            style: TextStyle(color: palette.textMuted, height: 1.35),
          ),
          const SizedBox(height: 14),
          Text(
            CustomerText.radarNameLabel.current,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _ResponsivePair(
            first: _field(
              key: const Key('customer_region_radar_first_name'),
              controller: _firstNameCtrl,
              label: CustomerText.radarFirstName.current,
              palette: palette,
            ),
            second: _field(
              key: const Key('customer_region_radar_last_name'),
              controller: _lastNameCtrl,
              label: CustomerText.radarLastName.current,
              palette: palette,
            ),
          ),
          const SizedBox(height: 12),
          _field(
            key: const Key('customer_region_radar_email'),
            controller: _emailCtrl,
            label: CustomerText.radarEmailLabel.current,
            palette: palette,
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _field(
            key: const Key('customer_region_radar_phone'),
            controller: _phoneCtrl,
            label: CustomerText.radarPhoneLabel.current,
            palette: palette,
            keyboard: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('customer_region_radar_submit'),
            style: FilledButton.styleFrom(
              backgroundColor: palette.gold,
              foregroundColor: customerOnGold(palette),
              disabledBackgroundColor: palette.border,
              disabledForegroundColor: palette.textMuted,
            ),
            onPressed: (_submitting || _submitted) ? null : _submit,
            child: Text(
              _submitting
                  ? CustomerText.radarSending.current
                  : CustomerText.radarCtaInterest.current,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            CustomerText.radarNoRide.current,
            style: TextStyle(color: palette.textMuted, height: 1.35),
          ),
          if (_formError != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _formError!,
              key: const Key('customer_region_radar_form_error'),
              style: TextStyle(color: palette.textPrimary),
            ),
          ],
          if (_formSuccess != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _formSuccess!,
              key: const Key('customer_region_radar_form_success'),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    required CustomerThemePalette palette,
    TextInputType? keyboard,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: keyboard,
      style: TextStyle(color: palette.textPrimary),
      cursorColor: palette.gold,
      decoration: InputDecoration(
        hintText: label,
        hintStyle: TextStyle(color: palette.textMuted),
        filled: true,
        fillColor: palette.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: palette.gold, width: 1.6),
        ),
      ),
    );
  }
}

class _HeroIntro extends StatelessWidget {
  const _HeroIntro({required this.palette});

  final CustomerThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final logoHeight = width >= 600 ? 40.0 : 34.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Image.asset(
              'assets/fluxidi/fluxidi_radar_hero.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.78),
                    Colors.black.withValues(alpha: 0.28),
                    Colors.black.withValues(alpha: 0.08),
                  ],
                  stops: const <double>[0, 0.55, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Image.asset(
                  key: const Key('customer_region_radar_logo'),
                  'assets/fluxidi/fluxidi_logo_horizontal_gold.png',
                  height: logoHeight,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 14),
                Text(
                  CustomerText.radarKicker.current,
                  style: TextStyle(
                    color: palette.gold,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  CustomerText.radarHeadline.current,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  CustomerText.radarLead.current,
                  style: const TextStyle(
                    color: Color(0xFFF2F2F2),
                    height: 1.4,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _TrustChip(label: CustomerText.radarTrustLocal.current),
                    _TrustChip(label: CustomerText.radarTrustPrices.current),
                    _TrustChip(label: CustomerText.radarTrustNoFee.current),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _RegionControls extends StatelessWidget {
  const _RegionControls({
    required this.palette,
    required this.country,
    required this.postcode,
    required this.lookingUp,
    required this.onCountry,
    required this.onView,
    this.sideBySide = false,
  });

  final CustomerThemePalette palette;
  final String country;
  final TextEditingController postcode;
  final bool lookingUp;
  final ValueChanged<String> onCountry;
  final VoidCallback? onView;
  final bool sideBySide;

  @override
  Widget build(BuildContext context) {
    return _ResponsivePair(
      forceRow: sideBySide,
      first: InputDecorator(
        decoration: InputDecoration(
          labelText: CustomerText.radarCountryLabel.current,
          labelStyle: TextStyle(color: palette.textMuted),
          filled: true,
          fillColor: palette.surface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: palette.border),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('customer_region_radar_country'),
            value: country,
            isExpanded: true,
            dropdownColor: palette.surface,
            style: TextStyle(color: palette.textPrimary),
            items: <DropdownMenuItem<String>>[
              for (final code in kRegionRadarCountryCodes)
                DropdownMenuItem<String>(
                  value: code,
                  child: Text(
                    regionRadarCountryName(code, appConfig.currentLanguage),
                  ),
                ),
            ],
            onChanged: (next) {
              if (next != null) onCountry(next);
            },
          ),
        ),
      ),
      second: TextField(
        key: const Key('customer_region_radar_postcode'),
        controller: postcode,
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(color: palette.textPrimary),
        decoration: InputDecoration(
          hintText: CustomerText.radarPostcodeLabel.current,
          hintStyle: TextStyle(color: palette.textMuted),
          filled: true,
          fillColor: palette.surface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: palette.gold, width: 1.6),
          ),
        ),
      ),
      trailing: SizedBox(
        height: 56,
        child: FilledButton(
          key: const Key('customer_region_radar_view'),
          style: FilledButton.styleFrom(
            backgroundColor: palette.gold,
            foregroundColor: customerOnGold(palette),
            disabledBackgroundColor: palette.border,
            disabledForegroundColor: palette.textMuted,
          ),
          onPressed: onView,
          child: Text(
            lookingUp
                ? CustomerText.radarSearching.current
                : CustomerText.radarViewRegion.current,
          ),
        ),
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({
    required this.first,
    required this.second,
    this.trailing,
    this.forceRow = false,
  });

  final Widget first;
  final Widget second;
  final Widget? trailing;
  final bool forceRow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = !forceRow && constraints.maxWidth < 560;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              first,
              const SizedBox(height: 10),
              second,
              if (trailing != null) ...<Widget>[
                const SizedBox(height: 10),
                trailing!,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.palette, required this.child});

  final CustomerThemePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _MapBanner extends StatelessWidget {
  const _MapBanner({required this.palette, required this.title});

  final CustomerThemePalette palette;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _InterestBadge extends StatelessWidget {
  const _InterestBadge({
    required this.palette,
    required this.snapshot,
  });

  final CustomerThemePalette palette;
  final RegionRadarSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('customer_region_radar_count'),
      constraints: const BoxConstraints(maxWidth: 168),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: palette.gold,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            snapshot.displayCount,
            style: TextStyle(
              color: customerOnGold(palette),
              fontWeight: FontWeight.w800,
              fontSize: 28,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            CustomerText.radarCountLabel.current,
            style: TextStyle(
              color: customerOnGold(palette),
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionRadarOverlayMarkers extends StatelessWidget {
  const _RegionRadarOverlayMarkers({
    required this.markers,
    required this.pulseOwn,
    required this.pixels,
    required this.onTap,
  });

  final List<RegionRadarMapMarker> markers;
  final bool pulseOwn;
  final Map<String, Offset> pixels;
  final ValueChanged<RegionRadarMapMarker> onTap;

  @override
  Widget build(BuildContext context) {
    if (markers.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final marker in markers)
          _positionedMarker(
            marker: marker,
            child: _LabeledRadarMarker(
              marker: marker,
              pulse: pulseOwn && marker.kind == RegionRadarMarkerKind.ownInterest,
              onTap: () => onTap(marker),
            ),
          ),
      ],
    );
  }

  Widget _positionedMarker({
    required RegionRadarMapMarker marker,
    required Widget child,
  }) {
    final pixel = pixels[marker.id];
    if (pixel == null) {
      return Align(alignment: Alignment.center, child: child);
    }
    return Positioned(
      left: pixel.dx - 72,
      top: pixel.dy - 36,
      width: 144,
      child: child,
    );
  }
}

class _LabeledRadarMarker extends StatelessWidget {
  const _LabeledRadarMarker({
    required this.marker,
    required this.onTap,
    this.pulse = false,
  });

  final RegionRadarMapMarker marker;
  final bool pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = marker.kind;
    final selected = kind == RegionRadarMarkerKind.selectedRegion;
    final own = kind == RegionRadarMarkerKind.ownInterest;
    final group = kind == RegionRadarMarkerKind.regionGroup;
    final label = selected
        ? CustomerText.radarSelectedRegion.current
        : own
        ? CustomerText.radarYourInterest.current
        : marker.displayCount;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                if (pulse) const _OwnInterestPulse(),
                Container(
                  key: Key(
                    selected
                        ? 'customer_region_radar_selected_marker'
                        : own
                        ? 'customer_region_radar_own_marker'
                        : 'customer_region_radar_region_marker',
                  ),
                  width: own ? 28 : 36,
                  height: own ? 28 : 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? const Color(0xFFF7F4EE)
                        : const Color(0xFFC4A35A),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFC4A35A)
                          : const Color(0xFFF3D48A),
                      width: own ? 3.2 : 2.2,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: own
                            ? const Color(0x66C4A35A)
                            : const Color(0x33000000),
                        blurRadius: own ? 10 : 4,
                        spreadRadius: own ? 2 : 0,
                      ),
                    ],
                  ),
                  child: group
                      ? Text(
                          marker.displayCount,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF2A2418),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            height: 1,
                          ),
                        )
                      : Icon(
                          selected
                              ? Icons.place_outlined
                              : Icons.favorite,
                          size: own ? 14 : 18,
                          color: const Color(0xFF8A6F2E),
                        ),
                ),
              ],
            ),
          ),
          if (label.trim().isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xF2FFFFFF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x33C4A35A)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Text(
                    label,
                    key: Key(
                      selected
                          ? 'customer_region_radar_selected_label'
                          : own
                          ? 'customer_region_radar_own_label'
                          : 'customer_region_radar_region_count_label',
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF2A2418),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OwnInterestPulse extends StatefulWidget {
  const _OwnInterestPulse();

  @override
  State<_OwnInterestPulse> createState() => _OwnInterestPulseState();
}

class _OwnInterestPulseState extends State<_OwnInterestPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        return Container(
          width: 28 + (22 * t),
          height: 28 + (22 * t),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFC4A35A).withValues(alpha: 0.7 * (1 - t)),
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.palette});

  final CustomerThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, String)>[
      (CustomerText.radarStep1Title.current, CustomerText.radarStep1Text.current),
      (CustomerText.radarStep2Title.current, CustomerText.radarStep2Text.current),
      (CustomerText.radarStep3Title.current, CustomerText.radarStep3Text.current),
    ];
    return Column(
      children: <Widget>[
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: palette.gold,
                  foregroundColor: customerOnGold(palette),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        steps[i].$1,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        steps[i].$2,
                        style: TextStyle(color: palette.textMuted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
