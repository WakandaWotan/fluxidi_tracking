import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../driver_session_store.dart';
import 'driver_ride_alert.dart';
import 'driver_ride_alert_preferences.dart';

class DriverRideAlertSettingsPage extends StatefulWidget {
  const DriverRideAlertSettingsPage({
    super.key,
    required this.session,
    this.language = 'nl',
  });
  final ActiveDriverSession session;
  final String language;
  @override
  State<DriverRideAlertSettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<DriverRideAlertSettingsPage> {
  final _preferences = DriverRideAlertPreferences();
  bool _enabled = false, _available = false, _loading = true, _saving = false;
  String? _error;
  String t(String nl, String en, String fr, String es) =>
      switch (widget.language) {
        'en' => en,
        'fr' => fr,
        'es' => es,
        _ => nl,
      };
  bool get _current {
    final s = activeDriverSessionNotifier.value, expected = widget.session;
    return s != null &&
        s.isStandaloneLoginSession &&
        s.tenantId == expected.tenantId &&
        s.companyId == expected.companyId &&
        s.driverId == expected.driverId &&
        s.driverSessionToken == expected.driverSessionToken;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _preferences.flashlight(widget.session);
    final available = await DriverRideAlert.torchAvailable();
    if (mounted)
      setState(() {
        _enabled = enabled;
        _available = available;
        _loading = false;
      });
  }

  Future<void> _change(bool enabled) async {
    if (!_current || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (enabled && !await Permission.camera.request().isGranted) {
        throw StateError('camera_permission_required');
      }
      if (!mounted || !_current) return;
      await _preferences.setFlashlight(widget.session, enabled);
      if (mounted && _current) setState(() => _enabled = enabled);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = t(
            'Niet ingeschakeld. Controleer de cameratoestemming van Fluxidi.',
            'Not enabled. Check Fluxidi camera permission.',
            'Non activé. Vérifiez l’autorisation caméra de Fluxidi.',
            'No activado. Comprueba el permiso de cámara de Fluxidi.',
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        t(
          'Ritmeldingen',
          'Ride alerts',
          'Alertes de course',
          'Alertas de viaje',
        ),
      ),
    ),
    body: ValueListenableBuilder<ActiveDriverSession?>(
      valueListenable: activeDriverSessionNotifier,
      builder: (context, _, child) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t(
              'Geluid en trilling volgen je Android-meldingsinstellingen.',
              'Sound and vibration follow your Android notification settings.',
              'Le son et les vibrations suivent les réglages Android.',
              'El sonido y la vibración siguen los ajustes de Android.',
            ),
          ),
          SwitchListTile(
            key: const ValueKey('driver-ride-flash-opt-in'),
            title: Text(
              t(
                'Korte zaklampflitsen',
                'Brief flashlight flashes',
                'Brefs éclairs',
                'Destellos breves',
              ),
            ),
            subtitle: Text(
              t(
                'Alleen bij een nieuwe rit, met de app geopend. Standaard uit.',
                'Only for a new ride while the app is open. Off by default.',
                'Uniquement pour une nouvelle course, application ouverte. Désactivé par défaut.',
                'Solo para un viaje nuevo con la aplicación abierta. Desactivado por defecto.',
              ),
            ),
            value: _enabled,
            onChanged: !_loading && !_saving && _available && _current
                ? _change
                : null,
          ),
          if (!_loading && !_available)
            Text(
              t(
                'Zaklamp niet beschikbaar op dit toestel.',
                'Flashlight unavailable on this device.',
                'Lampe indisponible sur cet appareil.',
                'Linterna no disponible en este dispositivo.',
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
