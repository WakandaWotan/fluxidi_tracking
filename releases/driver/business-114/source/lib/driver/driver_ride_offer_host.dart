import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'driver_ride_alert.dart';
import 'driver_ride_alert_controller.dart';
import 'driver_ride_alert_preferences.dart';
import '../driver_session_store.dart';
import 'driver_ride_offer.dart';
import 'driver_ride_decision_memory.dart';
import 'driver_ride_offer_panel.dart';
import 'driver_ride_offer_presentation.dart';
import '../app_config.dart' show vehiclesNotifier;

/// Foreground cockpit only. This is not a background notification service.
class DriverRideOfferHost extends StatefulWidget {
  const DriverRideOfferHost({
    super.key,
    required this.child,
    required this.baseUrl,
    this.language = 'nl',
    this.inbox = false,
    this.loadSession,
    this.sessionListenable,
    this.clientFactory,
    this.alertController,
    this.decisionMemory,
    this.onAcceptanceReceived,
  });
  final Widget child;
  final String baseUrl, language;
  final bool inbox;
  final DriverRideAlertController? alertController;
  final DriverRideDecisionMemory? decisionMemory;
  // ACK starts canonical reads; it must never create a local assignment.
  final void Function(ActiveDriverSession owner, DriverRideOffer offer)?
      onAcceptanceReceived;
  // Transport/session seams keep lifecycle tests on the actual offer host.
  final Future<ActiveDriverSession?> Function()? loadSession;
  final ValueListenable<ActiveDriverSession?>? sessionListenable;
  final DriverRideOfferClient Function(String token, String vehicleId)?
  clientFactory;
  @override
  State<DriverRideOfferHost> createState() => _DriverRideOfferHostState();
}

class _DriverRideOfferHostState extends State<DriverRideOfferHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  DriverRideOffer? _offer;
  String? _token, _pendingAction, _error;
  bool _polling = false, _busy = false, _disposed = false;
  bool _presentationReceived = false;
  String? _deliveryToken, _deliveryVehicle;
  bool _deliverySuspended = false;
  int _ticks = 0;
  int _nextPollTick = 0;
  int _pollAfterMs = 10000;
  int _ownerEpoch = 0;
  int _viewEpoch = 0;
  bool _loaded = false;
  String? _inboxError;
  ActiveDriverSession? _observedOwner;
  DriverRideAlertController get _alerts => widget.alertController ?? DriverRideAlertController.instance;
  final _alertPreferences = DriverRideAlertPreferences();
  DriverRideDecisionMemory get _decisions => widget.decisionMemory ?? DriverRideDecisionMemory.instance;
  String _decisionKey(ActiveDriverSession owner, DriverRideOffer offer) => jsonEncode([
    owner.tenantId, owner.companyId, owner.driverId, owner.assignedVehicleId,
    owner.driverSessionToken, offer.id, offer.version,
  ]);
  void _decisionChanged() {
    final offer = _offer, owner = _sessions.value;
    if (_disposed || !mounted || offer == null || owner == null || owner.driverSessionToken != _token) return;
    final decision = _decisions.read(_decisionKey(owner, offer), DateTime.now().millisecondsSinceEpoch);
    if (decision == null) return;
    setState(() {
      _busy = decision.inFlight;
      _pendingAction = decision.confirmed ? null : decision.action;
      if (decision.confirmed) _offer = null;
    });
    if (decision.confirmed) _alerts.stop(owner: this);
  }
  ValueListenable<ActiveDriverSession?> get _sessions =>
      widget.sessionListenable ?? activeDriverSessionNotifier;
  Future<ActiveDriverSession?> _loadSession() =>
      widget.loadSession?.call() ?? DriverSessionStore.instance.load();
  DriverRideOfferClient _client(
    String token,
    String vehicleId, {
    ActiveDriverSession? owner,
  }) =>
      widget.clientFactory?.call(token, vehicleId) ??
      DriverRideOfferClient(
        baseUrl: widget.baseUrl,
        token: token,
        vehicleId: vehicleId,
        driverId: owner?.driverId,
        tenantId: owner?.tenantId,
        companyId: owner?.companyId,
      );
  bool _sameOwner(ActiveDriverSession? a, ActiveDriverSession? b) =>
      a != null &&
      b != null &&
      a.isStandaloneLoginSession &&
      b.isStandaloneLoginSession &&
      a.tenantId == b.tenantId &&
      a.companyId == b.companyId &&
      a.driverId == b.driverId &&
      a.assignedVehicleId == b.assignedVehicleId &&
      a.driverSessionToken == b.driverSessionToken;

  void _ownerChanged() {
    final next = _sessions.value;
    if (_sameOwner(_observedOwner, next) ||
        (_observedOwner == null && next == null))
      return;
    _observedOwner = next;
    _ownerEpoch++;
    _viewEpoch++;
    _nextPollTick = 0;
    _deliverySuspended = false;
    _suspendDelivery();
    _alerts.stop(owner: this);
    if (!_disposed && mounted)
      setState(() {
        _offer = null;
        _token = null;
        _pendingAction = null;
        _error = null;
        _busy = false;
        _presentationReceived = false;
        _loaded = false;
        _inboxError = null;
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_poll()));
  }

  bool get _visible =>
      !_disposed &&
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      (ModalRoute.of(context)?.isCurrent ?? true);
  String message(String nl, String en, String fr, String es) =>
      switch (widget.language) {
        'en' => en,
        'fr' => fr,
        'es' => es,
        _ => nl,
      };
  @override
  void initState() {
    super.initState();
    _observedOwner = _sessions.value;
    _sessions.addListener(_ownerChanged);
    _decisions.addListener(_decisionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_poll()));
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_visible) {
        _suspendDelivery(allowBackground: true);
        _alerts.stop(owner: this, retainBackground: true);
        return;
      }
      if (_offer != null) setState(() {});
      if (_offer?.secondsRemaining(DateTime.now().millisecondsSinceEpoch) == 0)
        _alerts.stop(owner: this);
      if (++_ticks >= _nextPollTick) unawaited(_poll());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_visible) _alerts.stop(owner: this, retainBackground: true);
  }

  @override
  void didUpdateWidget(covariant DriverRideOfferHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.decisionMemory != widget.decisionMemory) {
      (oldWidget.decisionMemory ?? DriverRideDecisionMemory.instance).removeListener(_decisionChanged);
      _decisions.addListener(_decisionChanged);
      _decisionChanged();
    }
    if (oldWidget.sessionListenable != widget.sessionListenable) {
      (oldWidget.sessionListenable ?? activeDriverSessionNotifier)
          .removeListener(_ownerChanged);
      _sessions.addListener(_ownerChanged);
      _ownerChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _viewEpoch++;
    if (state != AppLifecycleState.resumed)
      _suspendDelivery(allowBackground: true);
    if (state != AppLifecycleState.resumed) _alerts.stop(owner: this, retainBackground: true);
    if (state != AppLifecycleState.resumed && mounted)
      setState(() {
        _offer = null;
        _token = null;
        _pendingAction = null;
        _error = null;
        _busy = false;
      });
    if (state == AppLifecycleState.resumed) unawaited(_poll());
  }

  Future<void> _poll() async {
    if (_polling || _busy || !_visible) return;
    _polling = true;
    _nextPollTick = _ticks + (_pollAfterMs / 1000).ceil();
    final epoch = _viewEpoch;
    final ownerEpoch = _ownerEpoch;
    DriverRideOfferClient? client;
    try {
      final session = await _loadSession();
      if (session == null ||
          !session.isStandaloneLoginSession ||
          [
            session.driverSessionToken,
            session.tenantId,
            session.companyId,
            session.driverId,
            session.assignedVehicleId,
          ].any((value) => (value ?? '').trim().isEmpty)) {
        if (_visible && epoch == _viewEpoch) {
          setState(() {
            _offer = null;
            _inboxError = message(
              'Meld je aan als chauffeur om je aanbiedingen te bekijken.',
              'Sign in as a driver to view your offers.',
              'Connectez-vous comme chauffeur pour voir vos demandes.',
              'Inicia sesión como conductor para ver tus ofertas.',
            );
          });
          _alerts.stop(owner: this);
        }
        return;
      }
      if (!_visible ||
          epoch != _viewEpoch ||
          !_sameOwner(session, _sessions.value))
        return;
      client = _client(
        session.driverSessionToken!,
        session.assignedVehicleId ?? '',
        owner: session,
      );
      _deliveryToken = session.driverSessionToken;
      _deliveryVehicle = session.assignedVehicleId;
      _deliverySuspended = false;
      final offers = await client.offers();
      if (!_visible ||
          epoch != _viewEpoch ||
          !_sameOwner(session, _sessions.value))
        return;
      _pollAfterMs = client.pollAfterMs;
      _nextPollTick = _ticks + (_pollAfterMs / 1000).ceil();
      final candidates = offers.where(
        (offer) =>
            offer.secondsRemaining(DateTime.now().millisecondsSinceEpoch) > 0 &&
            _decisions.read(_decisionKey(session, offer), DateTime.now().millisecondsSinceEpoch)?.confirmed != true,
      );
      final next = candidates.isEmpty ? null : candidates.first;
      final changed =
          next?.id != _offer?.id ||
          next?.version != _offer?.version ||
          _token != session.driverSessionToken;
      setState(() {
        _offer = next;
        _loaded = true;
        _inboxError = null;
        _token = session.driverSessionToken;
        if (changed) {
          _presentationReceived = false;
          final decision = next == null ? null : _decisions.read(
            _decisionKey(session, next), DateTime.now().millisecondsSinceEpoch);
          _pendingAction = decision?.action;
          _busy = decision?.inFlight ?? false;
          _error = null;
          if (decision != null && !decision.inFlight) _error = _unconfirmedDecisionMessage();
        }
      });
      if (next == null) _alerts.stop(owner: this);
      if (next != null) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_updateAlert()));
      if (next != null && !_presentationReceived) {
        // Wait for the rendered popup, then retry an uncertain receipt on the
        // next poll. The server retains the first display time across retries.
        await WidgetsBinding.instance.endOfFrame;
        if (!_visible ||
            epoch != _viewEpoch ||
            !_sameOwner(session, _sessions.value) ||
            _offer?.id != next.id ||
            _token != session.driverSessionToken)
          return;
        await DriverRideAlert.presented(next.id);
        final received = await client.received(next);
        if (_visible &&
            epoch == _viewEpoch &&
            _sameOwner(session, _sessions.value) &&
            _offer?.id == next.id &&
            _token == session.driverSessionToken)
          setState(() {
            if (received != null) _offer = received;
            _presentationReceived = true;
          });
        unawaited(_updateAlert());
      }
      for (final receipt in client.scheduledReadiness) {
        bool current() => _visible && epoch == _viewEpoch &&
            _sameOwner(session, _sessions.value);
        if (!current()) return;
        await client.acknowledgeScheduledReadiness(receipt, isCurrent: current);
      }
    } catch (_) {
      if (_visible && epoch == _viewEpoch)
        setState(() {
          _inboxError = message(
            'Aanbiedingen konden niet worden opgehaald. Probeer opnieuw.',
            'Offers could not be loaded. Retry.',
            'Impossible de charger les demandes. Réessayez.',
            'No se pudieron cargar las ofertas. Inténtalo de nuevo.',
          );
        });
      // Do not reveal backend bodies or credentials. Existing countdown remains
      // authoritative locally; no client-side reassignment on a network error.
    } finally {
      // A response can arrive after backgrounding. Withdraw once more after
      // that in-flight registration so it cannot leave a stale visible lease.
      if ((!_visible || epoch != _viewEpoch) && client != null) {
        try {
          if (ownerEpoch != _ownerEpoch ||
              _disposed ||
              !await DriverRideAlert.retainBackgroundDelivery(
                _deliveryToken ?? '',
              )) {
            await client.stopOffers();
          }
        } catch (_) {}
      }
      client?.close();
      _polling = false;
    }
  }

  void _suspendDelivery({bool allowBackground = false}) {
    if (_deliverySuspended ||
        _deliveryToken == null ||
        (_deliveryVehicle ?? '').isEmpty)
      return;
    _deliverySuspended = true;
    final ownerEpoch = _ownerEpoch;
    final token = _deliveryToken!;
    final client = _client(_deliveryToken!, _deliveryVehicle!);
    unawaited(() async {
      try {
        final retained =
            allowBackground &&
            await DriverRideAlert.retainBackgroundDelivery(token);
        if (!retained || ownerEpoch != _ownerEpoch || _disposed)
          await client.stopOffers();
      } catch (_) {
      } finally {
        client.close();
      }
    }());
  }

  Future<void> _updateAlert() async {
    final offer = _offer, owner = _sessions.value, epoch = _viewEpoch;
    bool current() => _visible &&
        epoch == _viewEpoch && _sameOwner(owner, _sessions.value) &&
        owner?.driverSessionToken == _token && _offer?.id == offer?.id &&
        _offer?.version == offer?.version;
    if (offer == null || owner == null || !current()) { _alerts.stop(owner: this); return; }
    final flash = await _alertPreferences.flashlight(owner).timeout(
      const Duration(milliseconds: 150), onTimeout: () => false);
    if (!current()) return;
    _alerts.present(owner: this,
      identity: jsonEncode([owner.tenantId, owner.companyId, owner.driverId,
        owner.driverSessionToken, offer.id, offer.version]),
      deadlineMs: _offer!.deadlineMs, flashlight: flash, offerScope: {
        'tenant_id': owner.tenantId, 'company_id': owner.companyId,
        'driver_id': owner.driverId, 'vehicle_id': offer.vehicleId,
        'offer_id': offer.id, 'version': offer.version, 'deadline_ms': _offer!.deadlineMs,
      });
  }

  String _unconfirmedDecisionMessage() => message(
    'Antwoord niet bevestigd. Probeer dezelfde keuze opnieuw.',
    'Response unconfirmed. Retry the same choice.',
    'Réponse non confirmée. Réessayez le même choix.',
    'Respuesta sin confirmar. Repite la misma opción.',
  );

  Future<void> _decide(String action) async {
    final offer = _offer, token = _token;
    final epoch = _viewEpoch;
    final owner = _sessions.value;
    if (!_visible ||
        _busy ||
        owner == null ||
        offer == null ||
        token == null ||
        offer.secondsRemaining(DateTime.now().millisecondsSinceEpoch) == 0 ||
        (_pendingAction != null && action != _pendingAction))
      return;
    final memory = _decisions;
    final decision = memory.begin(_decisionKey(owner, offer), action,
      offer.deadlineMs, DateTime.now().millisecondsSinceEpoch);
    if (decision == null) return;
    setState(() {
      _busy = true;
      _pendingAction = action;
      _error = null;
    });
    final client = _client(token, offer.vehicleId, owner: owner);
    try {
      final session = await _loadSession();
      if (!_visible ||
          epoch != _viewEpoch ||
          !_sameOwner(owner, session) ||
          !_sameOwner(session, _sessions.value) ||
          session?.driverSessionToken != token ||
          session?.assignedVehicleId != offer.vehicleId)
        throw StateError('driver_changed');
      if (offer.secondsRemaining(DateTime.now().millisecondsSinceEpoch) == 0)
        throw StateError('offer_expired');
      await client.decide(offer, action);
      unawaited(DriverRideAlert.stopOffer({
        'tenant_id': owner.tenantId, 'company_id': owner.companyId,
        'driver_id': owner.driverId, 'vehicle_id': offer.vehicleId,
        'offer_id': offer.id, 'version': offer.version,
      }));
      // Record the ACK even when this view was covered, backgrounded or disposed.
      // A remounted host for this exact actor/offer cannot ask for acceptance again.
      decision.confirmed = true;
      if (action == 'accept' && _sameOwner(owner, _sessions.value)) {
        // A covered inbox still refreshes its owning home, never another actor.
        widget.onAcceptanceReceived?.call(owner, offer);
      }
      if (mounted &&
          _visible &&
          epoch == _viewEpoch &&
          _token == token &&
          _offer?.id == offer.id && _offer?.version == offer.version) {
        _alerts.stop(owner: this);
        setState(() {
          _offer = null;
          _pendingAction = null;
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              action == 'accept'
                  ? message(
                      'Acceptatie ontvangen. Toewijzing wordt bevestigd.',
                      'Acceptance received. Assignment is being confirmed.',
                      'Acceptation reçue. Attribution en cours de confirmation.',
                      'Aceptación recibida. Se está confirmando la asignación.',
                    )
                  : message(
                      'Rit geweigerd.',
                      'Ride declined.',
                      'Course refusée.',
                      'Viaje rechazado.',
                    ),
            ),
          ),
        );
      }
    } catch (error) {
      if (_visible && epoch == _viewEpoch && _token == token)
        setState(
          () => _error = error is StateError && error.message == 'offer_expired'
              ? message(
                  'Dit ritvoorstel is verlopen. Controleer je openstaande aanbiedingen.',
                  'This offer has expired. Check your pending offers.',
                  'Cette proposition a expiré. Consultez vos offres en attente.',
                  'Esta oferta ha caducado. Revisa tus ofertas pendientes.',
                )
              : _unconfirmedDecisionMessage(),
        );
    } finally {
      memory.complete(decision);
      client.close();
      if (!_disposed && mounted && _sameOwner(owner, _sessions.value)) {
        setState(() => _busy = false);
        if (_visible && epoch != _viewEpoch) unawaited(_poll());
      }
    }
  }

  @override
  void dispose() {
    _suspendDelivery();
    _sessions.removeListener(_ownerChanged);
    _decisions.removeListener(_decisionChanged);
    _disposed = true;
    _alerts.stop(owner: this);
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (!widget.inbox)
        widget.child
      else
        Scaffold(
          appBar: AppBar(
            title: Text(
              message(
                'Ritaanbiedingen',
                'Ride offers',
                'Demandes de course',
                'Ofertas de viaje',
              ),
            ),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_taxi_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _inboxError ??
                        (_loaded
                            ? message(
                                'Geen openstaande ritaanbiedingen.',
                                'No pending ride offers.',
                                'Aucune demande en attente.',
                                'No hay ofertas pendientes.',
                              )
                            : message(
                                'Aanbiedingen ophalen…',
                                'Loading offers…',
                                'Chargement des demandes…',
                                'Cargando ofertas…',
                              )),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_poll()),
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      message(
                        'Vernieuwen',
                        'Refresh',
                        'Actualiser',
                        'Actualizar',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (_offer != null)
        Positioned.fill(
          child: DriverRideOfferPanel(
            offer: _offer!,
            vehiclePresentation: driverRideOfferVehiclePresentation(
              vehicleId: _offer!.vehicleId,
              session: _sessions.value,
              vehicles: vehiclesNotifier.value,
            ),
            nowMs: DateTime.now().millisecondsSinceEpoch,
            language: widget.language,
            busy: _busy,
            pendingAction: _pendingAction,
            error: _error,
            onDecision: (action) => unawaited(_decide(action)),
          ),
        ),
    ],
  );
}
