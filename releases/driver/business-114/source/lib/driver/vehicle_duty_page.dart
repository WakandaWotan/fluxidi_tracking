import 'dart:math';
import 'package:flutter/material.dart';
import 'vehicle_duty_client.dart';
import 'vehicle_duty_report.dart';

class VehicleDutyPage extends StatefulWidget {
  const VehicleDutyPage({super.key, required this.client});
  final VehicleDutyClient client;
  @override
  State<VehicleDutyPage> createState() => _VehicleDutyPageState();
}

class _VehicleDutyPageState extends State<VehicleDutyPage> {
  Map<String, dynamic>? _state, _pending;
  final List<Map<String, dynamic>> _history = [];
  String? _cursor, _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    widget.client.close();
    super.dispose();
  }

  String _id() => List.generate(
    24,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
  String _duration(dynamic ms) {
    if (ms is! num || ms < 0) return '—';
    final minutes = (ms / 60000).floor();
    return '${minutes ~/ 60} u ${minutes % 60} min';
  }

  Future<void> _load() async {
    try {
      final state = await widget.client.state();
      final history = await widget.client.history();
      final rows = (history['items'] as List).cast<Map<String, dynamic>>();
      VehicleDutyReport.fromRows(
        rows,
        driverId: widget.client.driverId,
        complete: history['cursor'] == null,
      );
      if (!mounted) return;
      setState(() {
        _state = state;
        _history
          ..clear()
          ..addAll(rows);
        _cursor = history['cursor'] as String?;
        _busy = false;
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = 'Dienstgegevens konden niet worden geladen.';
        });
    }
  }

  Future<void> _command(String action, Map<String, dynamic>? duty) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _pending ??= {
      'action': action,
      'duty_id': duty?['duty_id'] ?? _id(),
      'command_id': _id(),
      'expected_version': _state!['version'],
    };
    try {
      await widget.client.command(_pending!);
      _pending = null;
      await _load();
    } catch (error) {
      if (!mounted) return;
      if (error is VehicleDutyException &&
          [
            'active_ride_blocks_duty_change',
            'duty_version_conflict',
            'vehicle_session_mismatch',
          ].contains(error.code)) {
        _pending = null;
        await _load();
        if (!mounted) return;
      }
      setState(() {
        _busy = false;
        _error =
            error is VehicleDutyException &&
                error.code == 'active_ride_blocks_duty_change'
            ? 'Rond de actieve rit eerst af. Probeer daarna opnieuw.'
            : 'Geen bevestiging ontvangen. Probeer dezelfde opdracht opnieuw.';
      });
    }
  }

  Future<void> _more() async {
    setState(() {
      _busy = true;
    });
    try {
      final next = await widget.client.history(cursor: _cursor);
      final rows = [
        ..._history,
        ...(next['items'] as List).cast<Map<String, dynamic>>(),
      ];
      if (next['cursor'] != null && next['cursor'] == _cursor)
        throw const FormatException('duty_cursor_not_advancing');
      VehicleDutyReport.fromRows(
        rows,
        driverId: widget.client.driverId,
        complete: next['cursor'] == null,
      );
      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(rows);
        _cursor = next['cursor'] as String?;
        _busy = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = 'Meer diensten konden niet worden geladen.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final duties = (_state?['duties'] as List?) ?? [];
    final duty = duties.isEmpty
        ? null
        : Map<String, dynamic>.from(duties.single as Map);
    final paused = duty?['paused_at_ms'] != null;
    final report = VehicleDutyReport.fromRows(
      _history,
      driverId: widget.client.driverId,
      complete: _cursor == null,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Mijn voertuigdienst')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Voertuig: ${widget.client.vehicleId}'),
          const SizedBox(height: 12),
          Text(
            duty == null
                ? 'Geen actieve dienst'
                : paused
                ? 'Dienst gepauzeerd'
                : 'Dienst actief',
          ),
          const Text(
            'Online beschikbaarheid vereist daarnaast een actuele locatie en een geschikt verbonden toestel.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!),
            ),
          if (_pending != null)
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _command(_pending!['action'] as String, duty),
              child: const Text('Opdracht opnieuw proberen'),
            )
          else if (_state != null)
            Wrap(
              spacing: 8,
              children: [
                if (duty == null)
                  FilledButton(
                    onPressed: _busy ? null : () => _command('start', null),
                    child: const Text('Dienst starten'),
                  ),
                if (duty != null) ...[
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _command(paused ? 'resume' : 'pause', duty),
                    child: Text(paused ? 'Dienst hervatten' : 'Pauze'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _command('end', duty),
                    child: const Text('Dienst beëindigen'),
                  ),
                ],
              ],
            )
          else
            TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('Opnieuw laden'),
            ),
          const Divider(height: 32),
          const Text(
            'Afgeronde diensten',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Diensttijd en pauzes staan los van gereden rituren, kilometers en omzet in Mijn prestaties.',
          ),
          if (_history.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.complete
                          ? 'Totaal afgeronde diensten'
                          : 'Totaal geladen diensten (onvolledig)',
                    ),
                    Text('${report.count} diensten'),
                    Text('Aanwezig: ${_duration(report.elapsedMs)}'),
                    Text('Dienst zonder pauzes: ${_duration(report.dutyMs)}'),
                    Text('Pauzes: ${_duration(report.pauseMs)}'),
                  ],
                ),
              ),
            ),
          if (_history.isEmpty && !_busy)
            const Text('Nog geen afgeronde diensten.'),
          for (final row in _history)
            Card(
              child: ListTile(
                title: Text('Voertuig ${row['vehicle_id']}'),
                subtitle: Text(
                  '${DateTime.fromMillisecondsSinceEpoch(row['started_at_ms'] as int).toLocal()}\n'
                  'Tot ${DateTime.fromMillisecondsSinceEpoch(row['ended_at_ms'] as int).toLocal()}\n'
                  '${VehicleDutyReport.recoveryLabel(row).isEmpty ? '' : '${VehicleDutyReport.recoveryLabel(row)}\n'}'
                  'Dienst: ${_duration(row['summary']['duty_ms'])} · Pauze: ${_duration(row['summary']['pause_ms'])}',
                ),
              ),
            ),
          if (_cursor != null)
            TextButton(
              onPressed: _busy ? null : _more,
              child: const Text('Meer diensten'),
            ),
        ],
      ),
    );
  }
}
