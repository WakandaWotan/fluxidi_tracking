import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'nav_maneuver_sign.dart';
import 'nav_sign_resolver.dart';

/// NAV-SIGNAGE-VISUAL-RELEASE-GATE: internal proof surface for the navigation
/// signs.
///
/// Debug-only. [NavSignDebugCatalog] renders nothing in a release build, and
/// no release screen references it — it exists for developer inspection and
/// for the widget tests that capture the visual catalog.

/// One row of the catalog: an input event, what it should resolve to, and what
/// it actually resolved to.
@immutable
class NavSignDebugEntry {
  /// Human-readable description of the incoming navigation event.
  final String inputLabel;

  /// The event as the resolver receives it.
  final NavSignEvent event;

  /// Expected maneuver id, when the caller is asserting one.
  final NavSignManeuver? expected;

  const NavSignDebugEntry({
    required this.inputLabel,
    required this.event,
    this.expected,
  });

  NavSignResolution get resolution => resolveNavSign(event);

  /// True when the resolver agreed with [expected] (or nothing was expected).
  bool get mappingMatches =>
      expected == null || resolution.maneuver == expected;
}

/// The reference event for every one of the 34 signs.
///
/// This is the executable version of the mapping table: each entry is a
/// realistic Mapbox field combination and the sign it must produce. The debug
/// catalog and the simulation tests both read it, so a mapping can never be
/// documented in one place and implemented differently in another.
const List<NavSignDebugEntry> kNavSignReferenceEntries = <NavSignDebugEntry>[
  NavSignDebugEntry(
    inputLabel: 'type=turn modifier=straight',
    event: NavSignEvent(maneuverType: 'turn', maneuverModifier: 'straight'),
    expected: NavSignManeuver.straight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=- modifier=- (nothing classifiable)',
    event: NavSignEvent(),
    expected: NavSignManeuver.followRoute,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=turn modifier=slight left',
    event: NavSignEvent(maneuverType: 'turn', maneuverModifier: 'slight left'),
    expected: NavSignManeuver.slightLeft,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=turn modifier=slight right',
    event: NavSignEvent(maneuverType: 'turn', maneuverModifier: 'slight right'),
    expected: NavSignManeuver.slightRight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=turn modifier=left',
    event: NavSignEvent(maneuverType: 'turn', maneuverModifier: 'left'),
    expected: NavSignManeuver.turnLeft,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=turn modifier=right',
    event: NavSignEvent(maneuverType: 'turn', maneuverModifier: 'right'),
    expected: NavSignManeuver.turnRight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=turn modifier=sharp left',
    event: NavSignEvent(maneuverType: 'turn', maneuverModifier: 'sharp left'),
    expected: NavSignManeuver.sharpLeft,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=turn modifier=sharp right',
    event: NavSignEvent(maneuverType: 'turn', maneuverModifier: 'sharp right'),
    expected: NavSignManeuver.sharpRight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=turn modifier=uturn driving_side=right',
    event: NavSignEvent(
      maneuverType: 'turn',
      maneuverModifier: 'uturn',
      drivingSide: 'right',
    ),
    expected: NavSignManeuver.uturnLeft,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=turn modifier=uturn driving_side=left',
    event: NavSignEvent(
      maneuverType: 'turn',
      maneuverModifier: 'uturn',
      drivingSide: 'left',
    ),
    expected: NavSignManeuver.uturnRight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=roundabout exit=- (no trusted ordinal)',
    event: NavSignEvent(maneuverType: 'roundabout'),
    expected: NavSignManeuver.roundabout,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=roundabout exit=1',
    event: NavSignEvent(maneuverType: 'roundabout', exitNumber: '1'),
    expected: NavSignManeuver.roundaboutExit1,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=roundabout exit=2',
    event: NavSignEvent(maneuverType: 'roundabout', exitNumber: '2'),
    expected: NavSignManeuver.roundaboutExit2,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=roundabout exit=3',
    event: NavSignEvent(maneuverType: 'roundabout', exitNumber: '3'),
    expected: NavSignManeuver.roundaboutExit3,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=roundabout exit=4',
    event: NavSignEvent(maneuverType: 'roundabout', exitNumber: '4'),
    expected: NavSignManeuver.roundaboutExit4,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=fork modifier=left',
    event: NavSignEvent(maneuverType: 'fork', maneuverModifier: 'left'),
    expected: NavSignManeuver.forkLeft,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=fork modifier=straight',
    event: NavSignEvent(maneuverType: 'fork', maneuverModifier: 'straight'),
    expected: NavSignManeuver.forkStraight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=fork modifier=right',
    event: NavSignEvent(maneuverType: 'fork', maneuverModifier: 'right'),
    expected: NavSignManeuver.forkRight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=end of road modifier=left',
    event: NavSignEvent(maneuverType: 'end of road', maneuverModifier: 'left'),
    expected: NavSignManeuver.tLeft,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=end of road modifier=straight',
    event: NavSignEvent(
      maneuverType: 'end of road',
      maneuverModifier: 'straight',
    ),
    expected: NavSignManeuver.tStraight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=end of road modifier=right',
    event: NavSignEvent(maneuverType: 'end of road', maneuverModifier: 'right'),
    expected: NavSignManeuver.tRight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=merge modifier=left',
    event: NavSignEvent(maneuverType: 'merge', maneuverModifier: 'left'),
    expected: NavSignManeuver.mergeLeft,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=merge modifier=straight',
    event: NavSignEvent(maneuverType: 'merge', maneuverModifier: 'straight'),
    expected: NavSignManeuver.mergeStraight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=merge modifier=right',
    event: NavSignEvent(maneuverType: 'merge', maneuverModifier: 'right'),
    expected: NavSignManeuver.mergeRight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=on ramp modifier=left',
    event: NavSignEvent(maneuverType: 'on ramp', maneuverModifier: 'left'),
    expected: NavSignManeuver.rampLeft,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=on ramp modifier=right',
    event: NavSignEvent(maneuverType: 'on ramp', maneuverModifier: 'right'),
    expected: NavSignManeuver.rampRight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=off ramp modifier=left',
    event: NavSignEvent(maneuverType: 'off ramp', maneuverModifier: 'left'),
    expected: NavSignManeuver.exitLeft,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=off ramp modifier=right',
    event: NavSignEvent(maneuverType: 'off ramp', maneuverModifier: 'right'),
    expected: NavSignManeuver.exitRight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=continue modifier=slight left',
    event: NavSignEvent(
      maneuverType: 'continue',
      maneuverModifier: 'slight left',
    ),
    expected: NavSignManeuver.keepLeft,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=continue modifier=slight right',
    event: NavSignEvent(
      maneuverType: 'continue',
      maneuverModifier: 'slight right',
    ),
    expected: NavSignManeuver.keepRight,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=end of road modifier=- (junction only)',
    event: NavSignEvent(maneuverType: 'end of road'),
    expected: NavSignManeuver.roadEnd,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=arrive distance=320 m',
    event: NavSignEvent(maneuverType: 'arrive', distanceToManeuverMeters: 320),
    expected: NavSignManeuver.destinationAhead,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=arrive distance=8 m',
    event: NavSignEvent(maneuverType: 'arrive', distanceToManeuverMeters: 8),
    expected: NavSignManeuver.destinationReached,
  ),
  NavSignDebugEntry(
    inputLabel: 'type=depart modifier=left',
    event: NavSignEvent(maneuverType: 'depart', maneuverModifier: 'left'),
    expected: NavSignManeuver.departure,
  ),
];

/// Grid of sign cards: input event, resolved id, language, asset path, the
/// really-loaded image and a PASS/FAIL verdict.
class NavSignDebugCatalog extends StatelessWidget {
  const NavSignDebugCatalog({
    super.key,
    required this.languageCode,
    required this.entries,
    this.cardWidth = 220,
    this.bundle,
    this.probeAsset,
    this.title,
  });

  final String languageCode;
  final List<NavSignDebugEntry> entries;
  final double cardWidth;

  /// Overridable so tests can read from a controlled bundle.
  final AssetBundle? bundle;

  /// Overrides how a card decides whether its plate loaded.
  ///
  /// Widget tests run in a fake-async zone where a real bundle read never
  /// completes, so they resolve the loads up front and hand the answers in.
  final Future<bool> Function(String assetPath)? probeAsset;

  final String? title;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final resolvedLanguage = resolveNavSignLanguageCode(languageCode);
    return ColoredBox(
      color: const Color(0xFFEEF2F7),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title ??
                  'Fluxidi navigation signs — $resolvedLanguage '
                      '(${entries.length} cases)',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 10),
            // Scrolls when the surface is shorter than the grid, so the
            // catalog stays usable on a phone as well as on a wide capture.
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final entry in entries)
                      SizedBox(
                        width: cardWidth,
                        child: _NavSignDebugCard(
                          entry: entry,
                          languageCode: resolvedLanguage,
                          bundle: bundle,
                          probeAsset: probeAsset,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavSignDebugCard extends StatefulWidget {
  const _NavSignDebugCard({
    required this.entry,
    required this.languageCode,
    required this.bundle,
    required this.probeAsset,
  });

  final NavSignDebugEntry entry;
  final String languageCode;
  final AssetBundle? bundle;
  final Future<bool> Function(String assetPath)? probeAsset;

  @override
  State<_NavSignDebugCard> createState() => _NavSignDebugCardState();
}

class _NavSignDebugCardState extends State<_NavSignDebugCard> {
  late Future<bool> _loadProbe;
  late NavSignResolution _resolution;
  late String _path;

  @override
  void initState() {
    super.initState();
    _startProbe();
  }

  @override
  void didUpdateWidget(_NavSignDebugCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry ||
        oldWidget.languageCode != widget.languageCode ||
        oldWidget.bundle != widget.bundle ||
        oldWidget.probeAsset != widget.probeAsset) {
      _startProbe();
    }
  }

  // The probe must be created once per input, not per build, or the card
  // restarts its future on every frame and never settles.
  void _startProbe() {
    _resolution = widget.entry.resolution;
    _path = navSignAssetPath(
      languageCode: widget.languageCode,
      maneuver: _resolution.maneuver,
    );
    final probe = widget.probeAsset;
    if (probe != null) {
      _loadProbe = probe(_path);
      return;
    }
    final source = widget.bundle ?? rootBundle;
    _loadProbe = source
        .load(_path)
        .then((data) => data.lengthInBytes > 0)
        .catchError((Object _) => false);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final resolution = _resolution;
    final path = _path;
    return FutureBuilder<bool>(
      future: _loadProbe,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        final pass = entry.mappingMatches && loaded == true;
        final verdictColor = loaded == null
            ? const Color(0xFF6B7280)
            : (pass ? const Color(0xFF11804A) : const Color(0xFFB3261E));
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: verdictColor, width: 1.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: NavManeuverSign(
                  maneuver: resolution.maneuver,
                  languageCode: widget.languageCode,
                  size: 128,
                ),
              ),
              const SizedBox(height: 6),
              _line('in', entry.inputLabel),
              _line('id', resolution.maneuver.id),
              _line('lang', widget.languageCode),
              _line('path', path),
              _line(
                'load',
                loaded == null ? 'pending' : (loaded ? 'ok' : 'missing'),
              ),
              const SizedBox(height: 4),
              Text(
                loaded == null ? '…' : (pass ? 'PASS' : 'FAIL'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: verdictColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text(
        '$label: $value',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 9, color: Color(0xFF374151)),
      ),
    );
  }
}
