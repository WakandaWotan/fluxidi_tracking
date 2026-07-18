import 'dart:math' as math;

/// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 (Phase 1 fallback, Part A):
/// bounded adaptive cadence for the streetlevel follow camera pump used when
/// the native FollowPuck path is disabled (default in Phase 1).
///
/// This controller is a pure, side-effect-free policy. The widget owns the
/// timer and calls [currentTickMs] to schedule the next pump tick, then feeds
/// measured `applyLatencyMs` + rolling frame stats into [observe] at the end
/// of each tick.
///
/// Bounds:
///
///  * Runs at [minHz] .. [maxHz] Hz (defaults 6 .. 10).
///  * Steps down one Hz when apply-latency p95 > [stepDownApplyLatencyP95Ms]
///    OR frame p95 > [stepDownFrameP95Ms] OR the window contains
///    >= [stepDownFreezesOver100] frames over 100 ms.
///  * Steps up one Hz after [stepUpHealthyTicks] consecutive healthy ticks.
///
/// The primitive is intentionally left to the widget: this controller only
/// paces writes, it does not choose between `setCamera` / `easeTo` / `flyTo`.
/// The Phase 1 fallback keeps `setCamera` (instant, no animation to restart).
class NavAdaptiveCadenceController {
  NavAdaptiveCadenceController({
    int startHz = 10,
    int minHz = 6,
    int maxHz = 10,
    double stepDownApplyLatencyP95Ms = 130.0,
    double stepDownFrameP95Ms = 50.0,
    int stepDownFreezesOver100 = 2,
    int stepUpHealthyTicks = 24,
    int windowCapacity = 60,
  }) : assert(minHz > 0, 'minHz must be positive'),
       assert(maxHz >= minHz, 'maxHz must be >= minHz'),
       assert(
         startHz >= minHz && startHz <= maxHz,
         'startHz must be inside [minHz, maxHz]',
       ),
       _hz = startHz,
       _minHz = minHz,
       _maxHz = maxHz,
       _stepDownApplyLatencyP95Ms = stepDownApplyLatencyP95Ms,
       _stepDownFrameP95Ms = stepDownFrameP95Ms,
       _stepDownFreezesOver100 = stepDownFreezesOver100,
       _stepUpHealthyTicks = stepUpHealthyTicks,
       _windowCapacity = windowCapacity;

  int _hz;
  final int _minHz;
  final int _maxHz;
  final double _stepDownApplyLatencyP95Ms;
  final double _stepDownFrameP95Ms;
  final int _stepDownFreezesOver100;
  final int _stepUpHealthyTicks;
  final int _windowCapacity;
  final List<double> _applyLatencies = <double>[];
  int _healthyStreak = 0;

  int get currentHz => _hz;
  int get minHz => _minHz;
  int get maxHz => _maxHz;
  int get healthyStreak => _healthyStreak;

  /// Milliseconds between camera writes at the current Hz. Always > 0.
  int currentTickMs() => math.max(1, (1000.0 / _hz).round());

  /// Rolling apply-latency p95 (ms) over the observation window. Zero when the
  /// window is empty. Exposed for diagnostics/tests.
  double applyLatencyP95Ms() => _percentile(_applyLatencies, 0.95);

  /// Records one tick of observed health. Empty / non-finite values are
  /// ignored so a warm-up tick does not immediately step the cadence.
  void observe({
    required double applyLatencyMs,
    required double frameP95Ms,
    required int freezesOver100,
  }) {
    if (applyLatencyMs.isFinite && applyLatencyMs >= 0) {
      _applyLatencies.add(applyLatencyMs);
      if (_applyLatencies.length > _windowCapacity) {
        _applyLatencies.removeAt(0);
      }
    }
    final applyP95 = _percentile(_applyLatencies, 0.95);
    final unhealthy =
        applyP95 > _stepDownApplyLatencyP95Ms ||
        (frameP95Ms.isFinite && frameP95Ms > _stepDownFrameP95Ms) ||
        freezesOver100 >= _stepDownFreezesOver100;
    if (unhealthy) {
      _healthyStreak = 0;
      if (_hz > _minHz) {
        _hz = math.max(_minHz, _hz - 1);
      }
    } else {
      _healthyStreak += 1;
      if (_healthyStreak >= _stepUpHealthyTicks && _hz < _maxHz) {
        _hz = math.min(_maxHz, _hz + 1);
        _healthyStreak = 0;
      }
    }
  }

  double _percentile(List<double> samples, double q) {
    if (samples.isEmpty) return 0.0;
    final sorted = List<double>.from(samples)..sort();
    final idx = (q * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  void reset() {
    _hz = _maxHz;
    _healthyStreak = 0;
    _applyLatencies.clear();
  }
}
