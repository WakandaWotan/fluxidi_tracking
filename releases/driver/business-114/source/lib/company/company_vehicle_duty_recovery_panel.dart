import 'dart:math';
import 'package:flutter/material.dart';

class VehicleDutyRecoveryException implements Exception {
  const VehicleDutyRecoveryException(this.code);
  final String code;
}

class CompanyVehicleDutyRecoveryPanel extends StatefulWidget {
  const CompanyVehicleDutyRecoveryPanel({
    super.key,
    required this.devices,
    required this.loadState,
    required this.recover,
    this.language = 'nl',
  });
  final List<Map<String, dynamic>> devices;
  final Future<Map<String, dynamic>> Function() loadState;
  final Future<void> Function(Map<String, dynamic>) recover;
  final String language;
  @override
  State<CompanyVehicleDutyRecoveryPanel> createState() => _RecoveryState();
}

class _RecoveryState extends State<CompanyVehicleDutyRecoveryPanel> {
  Map<String, dynamic>? _state, _pending;
  bool _busy = true;
  String? _error;
  String text(String nl, String en, String fr, String es) =>
      switch (widget.language) {
        'en' => en,
        'fr' => fr,
        'es' => es,
        _ => nl,
      };
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await widget.loadState();
      if (mounted) setState(() => _state = state);
    } catch (_) {
      if (mounted)
        setState(() {
          _state = null;
          _error = text(
            'Open dienst kon niet worden geladen.',
            'Could not load open duty.',
            'Impossible de charger le service.',
            'No se pudo cargar el turno.',
          );
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover(Map<String, dynamic>? device) async {
    if (_pending == null) {
      final duty = (_state!['duties'] as List).single as Map;
      final reason = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(
            text(
              'Achtergebleven dienst afsluiten',
              'Close abandoned duty',
              'Clôturer le service restant',
              'Cerrar turno pendiente',
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                text(
                  'De dienst sluit nu af bij de oorspronkelijke chauffeur. Historiek blijft behouden. Een actieve of gereserveerde rit blokkeert dit.',
                  'The duty closes now for the original driver. History is preserved. Active or reserved rides block this.',
                  'Clôture maintenant pour le chauffeur initial. Historique conservé. Une course active ou réservée bloque cette action.',
                  'El turno termina ahora para el conductor original. Historial conservado. Un viaje activo o reservado bloquea esta acción.',
                ),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'device_lost'),
              child: Text(
                text(
                  'Toestel verloren',
                  'Device lost',
                  'Appareil perdu',
                  'Dispositivo perdido',
                ),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'device_replaced'),
              child: Text(
                text(
                  'Toestel vervangen',
                  'Device replaced',
                  'Appareil remplacé',
                  'Dispositivo reemplazado',
                ),
              ),
            ),
          ],
        ),
      );
      if (reason == null || !mounted) return;
      _pending = {
        'driver_id': duty['driver_id'],
        'duty_id': duty['duty_id'],
        'device_id': device!['device_id'],
        'expected_version': _state!['version'],
        'command_id': List.generate(
          32,
          (_) => Random.secure().nextInt(16).toRadixString(16),
        ).join(),
        'reason': reason,
      };
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.recover(Map.from(_pending!));
      _pending = null;
      await _load();
    } catch (error) {
      if (!mounted) return;
      final blocked =
          error is VehicleDutyRecoveryException &&
          [
            'active_ride_blocks_duty_change',
            'connected_device_blocks_duty_recovery',
            'device_must_be_unpaired_for_recovery',
            'duty_version_conflict',
            'duty_not_owned',
            'duty_recovery_device_mismatch',
            'capacity_baseline_required',
          ].contains(error.code);
      if (blocked) {
        _pending = null;
        await _load();
        if (!mounted) return;
      }
      setState(
        () => _error = blocked
            ? text(
                'Afsluiten geblokkeerd. Controleer ritten, toestellen en dienststatus.',
                'Closing blocked. Check rides, devices and duty status.',
                'Clôture bloquée. Vérifiez courses, appareils et service.',
                'Cierre bloqueado. Comprueba viajes, dispositivos y turno.',
              )
            : text(
                'Afsluiting niet bevestigd. Probeer dezelfde opdracht opnieuw.',
                'Closing unconfirmed. Retry the same command.',
                'Clôture non confirmée. Réessayez la même commande.',
                'Cierre sin confirmar. Reintenta la misma operación.',
              ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duties = _state?['duties'] as List? ?? [];
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (duties.isNotEmpty)
          Text(
            text(
              'Open dienst van chauffeur ${duties.single['driver_id']}',
              'Open duty for driver ${duties.single['driver_id']}',
              'Service ouvert du chauffeur ${duties.single['driver_id']}',
              'Turno abierto del conductor ${duties.single['driver_id']}',
            ),
          ),
        if (_pending != null)
          TextButton(
            onPressed: _busy ? null : () => _recover(null),
            child: Text(
              text(
                'Afsluiting opnieuw proberen',
                'Retry closing',
                'Réessayer la clôture',
                'Reintentar cierre',
              ),
            ),
          )
        else if (duties.isNotEmpty)
          for (final device in widget.devices.where(
            (row) =>
                row['status'] != 'paired' &&
                (duties.single['vehicle_device_id'] == null ||
                    row['device_id'] == duties.single['vehicle_device_id']),
          ))
            TextButton(
              onPressed: _busy ? null : () => _recover(device),
              child: Text(
                text(
                  'Dienst herstellen · ${device['device_id']}',
                  'Recover duty · ${device['device_id']}',
                  'Récupérer le service · ${device['device_id']}',
                  'Recuperar turno · ${device['device_id']}',
                ),
              ),
            ),
        if (!_busy && _pending == null)
          TextButton(
            onPressed: _load,
            child: Text(
              text(
                'Dienststatus vernieuwen',
                'Refresh duty status',
                'Actualiser le service',
                'Actualizar turno',
              ),
            ),
          ),
      ],
    );
  }
}
