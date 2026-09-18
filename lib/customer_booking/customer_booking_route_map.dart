import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_layout.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_camera.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_geometry.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/maps/fluxidi_static_route_preview.dart';

const Duration kCustomerBookingRouteDrawDuration = Duration(milliseconds: 900);

class CustomerBookingRouteMap extends StatefulWidget {
  const CustomerBookingRouteMap({
    super.key,
    required this.language,
    required this.palette,
    required this.pickup,
    required this.dropoff,
    this.stops = const <LimousineAddressValue>[],
    this.quote,
    this.quoteLoading = false,
    this.errorText,
    this.onRetry,
    this.pickupLocal,
    this.geometryClient,
    this.pickupNeedsConfirm = false,
    this.confirmLat,
    this.confirmLon,
    this.onConfirmPickup,
    this.pickupInspectSeq = 0,
    this.fitInsets = EdgeInsets.zero,
    this.onEditPickup,
    this.onEditDropoff,
    this.framed = true,
  });

  final AppLanguage language;
  final CustomerThemePalette palette;
  final LimousineAddressValue pickup;
  final LimousineAddressValue dropoff;
  final List<LimousineAddressValue> stops;
  final CompanyPlanQuoteResult? quote;
  final bool quoteLoading;
  final String? errorText;
  final VoidCallback? onRetry;
  final DateTime? pickupLocal;
  final CustomerBookingRouteGeometryClient? geometryClient;
  final bool pickupNeedsConfirm;
  final double? confirmLat;
  final double? confirmLon;
  final VoidCallback? onConfirmPickup;
  final int pickupInspectSeq;
  final EdgeInsets fitInsets;
  final VoidCallback? onEditPickup;
  final VoidCallback? onEditDropoff;
  final bool framed;

  @override
  State<CustomerBookingRouteMap> createState() =>
      _CustomerBookingRouteMapState();
}

class _CustomerBookingRouteMapState extends State<CustomerBookingRouteMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw;
  late final CustomerBookingRouteGeometryClient _geometryClient;
  CustomerBookingMapCamera _movedCamera = const CustomerBookingMapCamera(
    center: FluxidiMapLonLat(4.35, 50.85),
    zoom: 8,
  );
  CustomerBookingRouteGeometry? _geometry;
  String? _geometryError;
  bool _geometryLoading = false;
  bool _userMovedCamera = false;
  String _requestFingerprint = '';
  int _requestEpoch = 0;
  double _scaleStartZoom = 8;
  Size _viewport = Size.zero;
  EdgeInsets _appliedFitInsets = EdgeInsets.zero;
  final Stopwatch _visibleWatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _geometryClient =
        widget.geometryClient ?? CustomerBookingRouteGeometryClient();
    _draw = AnimationController(
      vsync: this,
      duration: kCustomerBookingRouteDrawDuration,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_syncGeometry());
    });
  }

  @override
  void didUpdateWidget(covariant CustomerBookingRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pickupNeedsConfirm != oldWidget.pickupNeedsConfirm ||
        widget.confirmLat != oldWidget.confirmLat ||
        widget.confirmLon != oldWidget.confirmLon ||
        widget.pickupInspectSeq != oldWidget.pickupInspectSeq) {
      _userMovedCamera = false;
    }
    if (_routeFingerprint() != _requestFingerprint) {
      unawaited(_syncGeometry());
    }
    _commitFitInsets(widget.fitInsets);
  }

  void _commitFitInsets(EdgeInsets next) {
    const slop = 28.0;
    if (_appliedFitInsets == EdgeInsets.zero ||
        (next.bottom - _appliedFitInsets.bottom).abs() > slop ||
        (next.top - _appliedFitInsets.top).abs() > slop ||
        (next.left - _appliedFitInsets.left).abs() > slop ||
        (next.right - _appliedFitInsets.right).abs() > slop) {
      _appliedFitInsets = next;
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  FluxidiMapLonLat? get _confirmPoint {
    return customerBookingLonLat(widget.confirmLat, widget.confirmLon);
  }

  FluxidiMapLonLat? get _pickupPoint {
    if (widget.pickupNeedsConfirm) {
      return _confirmPoint ??
          customerBookingLonLat(widget.pickup.lat, widget.pickup.lon);
    }
    return customerBookingLonLat(
      widget.quote?.pickupLat ?? widget.pickup.lat,
      widget.quote?.pickupLon ?? widget.pickup.lon,
    );
  }

  FluxidiMapLonLat? get _dropoffPoint {
    return customerBookingLonLat(
      widget.quote?.dropoffLat ?? widget.dropoff.lat,
      widget.quote?.dropoffLon ?? widget.dropoff.lon,
    );
  }

  List<FluxidiMapLonLat> get _stopPoints {
    return [
      for (final stop in widget.stops)
        ?customerBookingLonLat(stop.lat, stop.lon),
    ];
  }

  String _routeFingerprint() {
    return customerBookingRouteFingerprint(
      pickup: _pickupPoint,
      dropoff: _dropoffPoint,
      stops: _stopPoints,
    );
  }

  List<FluxidiMapLonLat> get _framePoints {
    if (widget.pickupNeedsConfirm && _pickupPoint != null) {
      return <FluxidiMapLonLat>[_pickupPoint!];
    }
    return <FluxidiMapLonLat>[
      if (_pickupPoint != null) _pickupPoint!,
      ..._stopPoints,
      if (_dropoffPoint != null) _dropoffPoint!,
      ...?_geometry?.points,
    ];
  }

  CustomerBookingMapCamera _cameraFor(Size size) {
    if (_userMovedCamera) return _movedCamera;
    return customerBookingFitCamera(
      points: _framePoints,
      size: size,
      origin: _pickupPoint,
      destination: _dropoffPoint,
      contentInsets: _appliedFitInsets == EdgeInsets.zero
          ? widget.fitInsets
          : _appliedFitInsets,
    );
  }

  Future<void> _syncGeometry() async {
    final pickup = _pickupPoint;
    final dropoff = _dropoffPoint;
    final fingerprint = _routeFingerprint();
    if (widget.pickupNeedsConfirm || pickup == null || dropoff == null) {
      _requestFingerprint = fingerprint;
      if (!mounted) return;
      setState(() {
        _geometry = null;
        _geometryError = null;
        _geometryLoading = false;
      });
      _draw.value = 0;
      return;
    }
    if (fingerprint == _requestFingerprint &&
        (_geometry != null || _geometryLoading || _geometryError != null)) {
      return;
    }
    if (!_geometryClient.canFetch) {
      _requestFingerprint = fingerprint;
      if (!mounted) return;
      setState(() {
        _geometry = null;
        _geometryError = null;
        _geometryLoading = false;
        _userMovedCamera = false;
      });
      return;
    }
    final epoch = ++_requestEpoch;
    _requestFingerprint = fingerprint;
    _visibleWatch
      ..reset()
      ..start();
    setState(() {
      _geometryLoading = true;
      _geometryError = null;
    });
    try {
      final result = await _geometryClient.fetch(
        pickup: pickup,
        dropoff: dropoff,
        stops: _stopPoints,
      );
      if (!mounted || epoch != _requestEpoch) return;
      _visibleWatch.stop();
      debugPrint(
        '[CUSTOMER_BOOKING][ROUTE] visible_ms=${_visibleWatch.elapsedMilliseconds} fingerprint=$fingerprint',
      );
      setState(() {
        _geometry = result.hasLine ? result : null;
        _geometryLoading = false;
        _geometryError = result.hasLine ? null : 'route_failed';
        _userMovedCamera = false;
      });
      if (result.hasLine) {
        _draw
          ..value = 0
          ..forward();
      }
    } catch (error) {
      if (!mounted || epoch != _requestEpoch) return;
      _visibleWatch.stop();
      debugPrint('[CUSTOMER_BOOKING][ROUTE][ERR] $error');
      setState(() {
        _geometry = null;
        _geometryLoading = false;
        _geometryError = error.toString();
      });
      _draw.value = 0;
    }
  }

  void _retry() {
    _requestFingerprint = '';
    unawaited(_syncGeometry());
    widget.onRetry?.call();
  }

  String get _statusText {
    if (widget.quoteLoading || _geometryLoading) {
      return kCustomerBookingRouteLoading.of(widget.language);
    }
    final raw = widget.errorText ?? _geometryError;
    final issue = customerBookingQuoteIssueFromRaw(raw);
    final hasRoute =
        (_geometry?.hasLine ?? false) || (widget.quote?.hasRoute ?? false);
    if (hasRoute &&
        (issue == kCustomerBookingIssueFailed ||
            issue == kCustomerBookingIssueNeedRoute)) {
      return '';
    }
    final failed = customerBookingQuoteErrorText(raw, widget.language);
    if (failed.isNotEmpty) return failed;
    if (widget.pickupNeedsConfirm ||
        (_pickupPoint == null && widget.pickup.displayText.trim().isNotEmpty)) {
      return kCustomerBookingConfirmPickup.of(widget.language);
    }
    if (_dropoffPoint == null && widget.dropoff.displayText.trim().isNotEmpty) {
      return kCustomerBookingConfirmDropoff.of(widget.language);
    }
    if (_pickupPoint == null || _dropoffPoint == null) {
      return kCustomerBookingMissingAddresses.of(widget.language);
    }
    return '';
  }

  String get _metricsText {
    if (widget.pickupNeedsConfirm) return '';
    final quote = widget.quote;
    final geometry = _geometry;
    final minutes = quote?.durationMin ?? geometry?.durationMin;
    final km = quote?.distanceKm ?? geometry?.distanceKm;
    if (minutes == null || km == null) return '';
    final kmText = km.toStringAsFixed(1).replaceAll('.', ',');
    return '$minutes min · $kmText km';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusText;
    final loading = widget.quoteLoading || _geometryLoading;
    final showError = !loading && status.isNotEmpty;
    _commitFitInsets(widget.fitInsets);
    final mapBody = LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            _viewport = size;
            final camera = _cameraFor(size);
            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFFDCE6DC)),
                Listener(
                  onPointerSignal: (event) {
                    if (event is! PointerScrollEvent) return;
                    final nextZoom = event.scrollDelta.dy > 0
                        ? camera.zoom - 0.35
                        : camera.zoom + 0.35;
                    setState(() {
                      _userMovedCamera = true;
                      _movedCamera = customerBookingZoomCamera(
                        camera: camera,
                        size: size,
                        focal: event.localPosition,
                        nextZoom: nextZoom,
                      );
                    });
                  },
                  child: GestureDetector(
                    onScaleStart: (_) => _scaleStartZoom = camera.zoom,
                    onScaleUpdate: (details) {
                      var next = customerBookingPanCamera(
                        camera,
                        details.focalPointDelta,
                      );
                      if ((details.scale - 1).abs() > 0.01) {
                        next = customerBookingZoomCamera(
                          camera: next,
                          size: size,
                          focal: details.localFocalPoint,
                          nextZoom: _scaleStartZoom +
                              math.log(details.scale.clamp(0.25, 4)) /
                                  math.ln2,
                        );
                      }
                      setState(() {
                        _userMovedCamera = true;
                        _movedCamera = next;
                      });
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Transform.rotate(
                          angle: -camera.bearingDeg * math.pi / 180,
                          child: _MapboxTileLayer(
                            camera: camera.copyWith(bearingDeg: 0),
                            size: size,
                            token: _geometryClient.token,
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _draw,
                          builder: (context, _) {
                            return CustomPaint(
                              key: kCustomerBookingRouteCanvasKey,
                              painter: _CustomerBookingRoutePainter(
                                camera: camera,
                                pickup: _pickupPoint,
                                dropoff: _dropoffPoint,
                                stops: _stopPoints,
                                route: _geometry?.points ??
                                    const <FluxidiMapLonLat>[],
                                progress: _draw.value,
                                gold: widget.palette.gold,
                              ),
                              child: const SizedBox.expand(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                ..._endpointLabels(size, camera),
                if (_metricsText.isNotEmpty)
                  Positioned(
                    left: _visibleHole(size).left + 8,
                    top: () {
                      final hole = _visibleHole(size);
                      const chipH = 32.0;
                      const gap = 6.0;
                      final destBottom = hole.top + 8 + chipH;
                      final pickupTop = hole.bottom - 8 - chipH;
                      var top = hole.center.dy - chipH / 2;
                      if (top < destBottom + gap) top = destBottom + gap;
                      if (top + chipH > pickupTop - gap) {
                        top = pickupTop - gap - chipH;
                      }
                      if (top < hole.top + 8) top = hole.top + 8;
                      return top;
                    }(),
                    child: _EndpointChip(
                      icon: Icons.schedule,
                      text: _metricsText,
                      palette: widget.palette,
                    ),
                  ),
                Positioned(
                  top: _visibleHole(size).top + 4,
                  right: size.width - _visibleHole(size).right + 4,
                  child: IconButton.filledTonal(
                    key: kCustomerBookingFitRouteKey,
                    tooltip: kCustomerBookingFitRoute.of(widget.language),
                    onPressed: () {
                      setState(() {
                        _userMovedCamera = false;
                        _appliedFitInsets = widget.fitInsets;
                        _movedCamera = customerBookingFitCamera(
                          points: _framePoints,
                          size: _viewport == Size.zero ? size : _viewport,
                          origin: _pickupPoint,
                          destination: _dropoffPoint,
                          contentInsets: widget.fitInsets,
                        );
                      });
                    },
                    icon: const Icon(Icons.center_focus_strong_outlined),
                  ),
                ),
                if (loading)
                  Align(
                    alignment: _geometry == null
                        ? Alignment.center
                        : Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _StatusCard(
                        palette: widget.palette,
                        child: Text(
                          kCustomerBookingRouteLoading.of(widget.language),
                          key: kCustomerBookingQuoteStatusKey,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ),
                  )
                else if (showError)
                  Align(
                    alignment: _geometry == null
                        ? Alignment.center
                        : Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _StatusCard(
                        palette: widget.palette,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              status,
                              key: kCustomerBookingQuoteStatusKey,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall,
                            ),
                            if (widget.pickupNeedsConfirm &&
                                widget.onConfirmPickup != null)
                              TextButton(
                                key: kCustomerBookingAddressConfirmMapKey,
                                onPressed: widget.onConfirmPickup,
                                child: Text(
                                  kCustomerBookingAddressConfirmMap.of(
                                    widget.language,
                                  ),
                                ),
                              )
                            else if (widget.onRetry != null)
                              TextButton(
                                key: kCustomerBookingQuoteRetryKey,
                                onPressed: _retry,
                                child: Text(
                                  kCustomerBookingRetry.of(widget.language),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
    if (!widget.framed) {
      return ClipRect(child: mapBody);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.palette.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: mapBody,
      ),
    );
  }

  EdgeInsets get _labelInsets =>
      _appliedFitInsets == EdgeInsets.zero ? widget.fitInsets : _appliedFitInsets;

  Rect _visibleHole(Size size) =>
      customerBookingVisibleMapHole(size, _labelInsets);

  List<Widget> _endpointLabels(Size size, CustomerBookingMapCamera camera) {
    const labelSize = Size(168, 32);
    final hole = _visibleHole(size);
    Widget? chip({
      required Key key,
      required FluxidiMapLonLat? point,
      required String raw,
      required String emptyLabel,
      required IconData icon,
      required Offset nudge,
      required bool pickup,
      VoidCallback? onTap,
    }) {
      final text = customerBookingCompactAddressLabel(raw).isEmpty
          ? emptyLabel
          : customerBookingCompactAddressLabel(raw);
      Offset pos;
      if (point == null) {
        pos = Offset(
          hole.left + 8,
          pickup ? hole.bottom - labelSize.height - 8 : hole.top + 8,
        );
      } else {
        final anchor = customerBookingProject(point, camera, size);
        pos = customerBookingClampMapLabel(
          anchor: anchor,
          size: size,
          visibleInsets: _labelInsets,
          labelSize: labelSize,
          nudge: nudge,
        );
      }
      return Positioned(
        left: pos.dx,
        top: pos.dy,
        child: _EndpointChip(
          key: key,
          icon: icon,
          text: text,
          palette: widget.palette,
          onTap: onTap,
        ),
      );
    }

    return [
      ?chip(
        key: kCustomerBookingMapPickupChipKey,
        point: _pickupPoint,
        raw: widget.pickup.displayText,
        emptyLabel: kCustomerBookingPickup.of(widget.language),
        icon: Icons.trip_origin,
        nudge: const Offset(12, -36),
        pickup: true,
        onTap: widget.onEditPickup,
      ),
      ?chip(
        key: kCustomerBookingMapDropoffChipKey,
        point: _dropoffPoint,
        raw: widget.dropoff.displayText,
        emptyLabel: kCustomerBookingDropoff.of(widget.language),
        icon: Icons.flag_outlined,
        nudge: const Offset(-120, 14),
        pickup: false,
        onTap: widget.onEditDropoff,
      ),
    ];
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.palette, required this.child});

  final CustomerThemePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: child,
      ),
    );
  }
}

class _EndpointChip extends StatelessWidget {
  const _EndpointChip({
    super.key,
    required this.icon,
    required this.text,
    required this.palette,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final CustomerThemePalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 168),
      child: Material(
        color: palette.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: palette.textPrimary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit_outlined, size: 14, color: palette.textMuted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapboxTileLayer extends StatelessWidget {
  const _MapboxTileLayer({
    required this.camera,
    required this.size,
    required this.token,
  });

  final CustomerBookingMapCamera camera;
  final Size size;
  final String token;

  @override
  Widget build(BuildContext context) {
    if (token.trim().isEmpty || size.width <= 0 || size.height <= 0) {
      return const SizedBox.expand();
    }
    final z = camera.zoom.floor().clamp(1, 16);
    final n = 1 << z;
    final scale = customerBookingWorldSize(camera.zoom);
    final tileSize = scale / n;
    final worldLeft =
        customerBookingMercatorX(camera.center.lon) * scale - size.width / 2;
    final worldTop =
        customerBookingMercatorY(camera.center.lat) * scale - size.height / 2;
    final minX = (worldLeft / tileSize).floor() - 1;
    final minY = (worldTop / tileSize).floor() - 1;
    final maxX = ((worldLeft + size.width) / tileSize).ceil() + 1;
    final maxY = ((worldTop + size.height) / tileSize).ceil() + 1;
    final children = <Widget>[];
    for (var x = minX; x <= maxX; x++) {
      for (var y = minY; y <= maxY; y++) {
        if (y < 0 || y >= n) continue;
        final wrappedX = ((x % n) + n) % n;
        children.add(
          Positioned(
            left: x * tileSize - worldLeft,
            top: y * tileSize - worldTop,
            width: tileSize,
            height: tileSize,
            child: Image.network(
              'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/$z/$wrappedX/$y@2x?access_token=$token',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) =>
              const ColoredBox(color: Color(0xFFDCE6DC)),
            ),
          ),
        );
      }
    }
    return Stack(clipBehavior: Clip.hardEdge, children: children);
  }
}

class _CustomerBookingRoutePainter extends CustomPainter {
  const _CustomerBookingRoutePainter({
    required this.camera,
    required this.pickup,
    required this.dropoff,
    required this.stops,
    required this.route,
    required this.progress,
    required this.gold,
  });

  final CustomerBookingMapCamera camera;
  final FluxidiMapLonLat? pickup;
  final FluxidiMapLonLat? dropoff;
  final List<FluxidiMapLonLat> stops;
  final List<FluxidiMapLonLat> route;
  final double progress;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final projected = [
      for (final point in route) customerBookingProject(point, camera, size),
    ];
    if (projected.length >= 2 && progress > 0) {
      final drawn = customerBookingRoutePrefix(projected, progress);
      final path = Path()..moveTo(drawn.first.dx, drawn.first.dy);
      for (var i = 1; i < drawn.length; i++) {
        path.lineTo(drawn[i].dx, drawn[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF1A1C16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    void marker(
      FluxidiMapLonLat? point,
      Color fill, {
      bool destination = false,
    }) {
      if (point == null) return;
      final offset = customerBookingProject(point, camera, size);
      final fillPaint = Paint()..color = fill;
      final ring = Paint()
        ..color = const Color(0xFF1A1C16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      if (destination) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: offset, width: 16, height: 16),
          const Radius.circular(3),
        );
        canvas.drawRRect(rect, fillPaint);
        canvas.drawRRect(rect, ring);
      } else {
        canvas.drawCircle(offset, 7, fillPaint);
        canvas.drawCircle(offset, 7, ring);
      }
    }

    for (final stop in stops) {
      marker(stop, const Color(0xFF4A4A4A));
    }
    marker(pickup, gold);
    marker(dropoff, gold, destination: true);
  }

  @override
  bool shouldRepaint(covariant _CustomerBookingRoutePainter oldDelegate) {
    return oldDelegate.camera.center.lat != camera.center.lat ||
        oldDelegate.camera.center.lon != camera.center.lon ||
        oldDelegate.camera.zoom != camera.zoom ||
        oldDelegate.progress != progress ||
        oldDelegate.route.length != route.length ||
        oldDelegate.gold != gold;
  }
}
