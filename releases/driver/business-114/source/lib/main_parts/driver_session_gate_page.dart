part of '../main.dart';

/// Standalone chauffeur entry. The dashboard is not mounted until the bearer
/// is accepted by the booking server. On resume it stays covered during a
/// recheck, preserving an active background tracking owner.
class DriverSessionGatePage extends StatefulWidget {
  const DriverSessionGatePage({
    super.key,
    this.newlyIssued = false,
    this.activateAfterSignIn = false,
    @visibleForTesting this.probe,
    @visibleForTesting this.dashboardBuilder,
  });

  /// True only immediately after a successful backend login/QR verification.
  final bool newlyIssued;
  final bool activateAfterSignIn;
  final Future<DriverSessionProbeResult> Function(ActiveDriverSession)? probe;
  final WidgetBuilder? dashboardBuilder;

  @override
  State<DriverSessionGatePage> createState() => _DriverSessionGatePageState();
}

class _DriverSessionGatePageState extends State<DriverSessionGatePage>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _verified = false;
  bool _unavailable = false;
  bool _invalid = false;
  int _requestEpoch = 0;
  DriverSignInActivation? _activation;
  bool _activationConfirmed = false;
  bool _activationUnavailable = false;
  final _dashboardKey = GlobalKey<_DriverHomePageState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.newlyIssued && !widget.activateAfterSignIn &&
        activeDriverSessionNotifier.value?.isStandaloneLoginSession == true &&
        (activeDriverSessionNotifier.value?.driverSessionToken ?? '')
            .trim()
            .isNotEmpty) {
      _checking = false;
      _verified = true;
    } else {
      _verify();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestEpoch++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _verify();
  }

  Future<void> _verify() async {
    final session = activeDriverSessionNotifier.value;
    final token = (session?.driverSessionToken ?? '').trim();
    final epoch = ++_requestEpoch;
    if (mounted) {
      setState(() {
        _checking = true;
        _unavailable = false;
      });
    }
    if (widget.newlyIssued && widget.activateAfterSignIn && !_activationConfirmed && session != null) {
      try {
        _activation ??= DriverSignInActivation(session);
        final captured = _activation!.session;
        await _activation!.activate(baseUrl: kBookingBaseUrl,
          isCurrent: () => mounted && identical(captured, activeDriverSessionNotifier.value));
        if (!mounted || epoch != _requestEpoch || !identical(session, activeDriverSessionNotifier.value)) return;
        setState(() {
          _activationConfirmed = true;
          _activationUnavailable = false;
          _checking = false;
          _verified = true;
          _unavailable = false;
          _invalid = false;
        });
      } catch (_) {
        if (!mounted || epoch != _requestEpoch) return;
        setState(() {
          _checking = false;
          _unavailable = true;
          _activationUnavailable = true;
        });
      }
      return;
    }
    final result = session == null ||
            !session.isStandaloneLoginSession ||
            (session.tenantId ?? '').trim().isEmpty ||
            (session.companyId ?? '').trim().isEmpty ||
            token.isEmpty
        ? DriverSessionProbeResult.invalid
        : await (widget.probe?.call(session) ??
            const DriverSessionProbe().check(
              bookingBaseUrl: kBookingBaseUrl,
              token: token,
            ));
    if (!mounted || epoch != _requestEpoch) return;
    if (!identical(session, activeDriverSessionNotifier.value)) {
      _verify();
      return;
    }
    if (result == DriverSessionProbeResult.invalid) {
      await DriverStartupPreference.instance.clear();
      await DriverSessionStore.instance.clear();
      if (!mounted || epoch != _requestEpoch) return;
      setState(() {
        _checking = false;
        _verified = false;
        _invalid = true;
      });
      return;
    }
    setState(() {
      _checking = false;
      _verified = result == DriverSessionProbeResult.valid || _verified;
      _unavailable = result == DriverSessionProbeResult.unavailable;
      _invalid = false;
    });
    if (result == DriverSessionProbeResult.valid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _requestEpoch && identical(session, activeDriverSessionNotifier.value)) {
          // Refresh the server state after foreground verification. This never
          // writes Available or lifts a pause; it restarts only permitted GPS.
          unawaited(_dashboardKey.currentState?._refreshDriverAvailabilityFromBackend(
            reason: 'authenticated_foreground', force: true));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invalid) return const ChauffeurLoginPage();
    // Keep an existing tracking owner mounted while the app checks on
    // foreground return. The opaque cover prevents use of stale data.
    return Stack(
      children: <Widget>[
        if (_verified)
          widget.dashboardBuilder?.call(context) ?? DriverHomePage(key: _dashboardKey),
        if (_checking || _unavailable || !_verified) Positioned.fill(
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: Center(
              child: _checking
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _activationUnavailable
                              ? 'Aanmelding gelukt. Online zetten is nog niet bevestigd. Controleer je verbinding of voertuigdienst en probeer opnieuw.'
                              : 'Sessiecontrole tijdelijk niet beschikbaar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _verify,
                          child: const Text('Opnieuw proberen'),
                        ),
                        if (_activationUnavailable) TextButton(
                          onPressed: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const ChauffeurLoginPage())),
                          child: const Text('Opnieuw aanmelden'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
