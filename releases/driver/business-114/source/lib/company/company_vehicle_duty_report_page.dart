import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../driver/vehicle_duty_report.dart';

class CompanyVehicleDutyReportClient {
  CompanyVehicleDutyReportClient({
    required this.baseUrl,
    required this.token,
    required this.companyId,
    required this.driverId,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String baseUrl, token, companyId, driverId;
  final http.Client _client;
  void close() => _client.close();
  Future<Map<String, dynamic>> history({String? cursor}) async {
    if ([token, companyId, driverId].any((value) => value.isEmpty))
      throw StateError('company_session_required');
    final response = await _client
        .post(
          Uri.parse('$baseUrl/admin/company/vehicle-duty-history'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'company_id': companyId,
            'driver_id': driverId,
            if (cursor != null) 'cursor': cursor,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final dynamic result = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        result is! Map<String, dynamic> ||
        result['ok'] != true ||
        result['items'] is! List ||
        result['cursor'] != null && result['cursor'] is! String) {
      throw const FormatException('invalid_duty_report');
    }
    for (final row in result['items'] as List) {
      VehicleDutyReport.validateRow(row, driverId);
      if (row['company_id'] != companyId)
        throw const FormatException('invalid_duty_report');
    }
    return result;
  }
}

class CompanyVehicleDutyReportPage extends StatefulWidget {
  const CompanyVehicleDutyReportPage({
    super.key,
    required this.client,
    required this.driverName,
  });
  final CompanyVehicleDutyReportClient client;
  final String driverName;
  @override
  State<CompanyVehicleDutyReportPage> createState() =>
      _CompanyVehicleDutyReportPageState();
}

class _CompanyVehicleDutyReportPageState
    extends State<CompanyVehicleDutyReportPage> {
  final List<Map<String, dynamic>> _rows = [];
  String? _cursor, _error;
  bool _busy = true, _loaded = false;
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

  String _duration(int ms) => '${ms ~/ 3600000} u ${(ms ~/ 60000) % 60} min';
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.history(cursor: _cursor);
      if (!mounted) return;
      final rows = [
        ..._rows,
        ...(result['items'] as List).cast<Map<String, dynamic>>(),
      ];
      if (result['cursor'] != null && result['cursor'] == _cursor)
        throw const FormatException('duty_cursor_not_advancing');
      VehicleDutyReport.fromRows(
        rows,
        driverId: widget.client.driverId,
        complete: result['cursor'] == null,
      );
      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
        _cursor = result['cursor'] as String?;
        _loaded = true;
        _busy = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = 'Diensthistoriek kon niet worden geladen.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = VehicleDutyReport.fromRows(
      _rows,
      driverId: widget.client.driverId,
      complete: _loaded && _cursor == null,
    );
    return Scaffold(
      appBar: AppBar(title: Text('Voertuigdiensten · ${widget.driverName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Afgeronde diensten per chauffeur, over alle gebruikte voertuigen. Diensttijd is geen gereden ritduur.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (_loaded)
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
          for (final row in _rows)
            Card(
              child: ListTile(
                title: Text('Voertuig ${row['vehicle_id']}'),
                subtitle: Text(
                  '${DateTime.fromMillisecondsSinceEpoch(row['started_at_ms'] as int).toLocal()}\n'
                  'Tot ${DateTime.fromMillisecondsSinceEpoch(row['ended_at_ms'] as int).toLocal()}\n'
                  '${VehicleDutyReport.recoveryLabel(row).isEmpty ? '' : '${VehicleDutyReport.recoveryLabel(row)}\n'}'
                  'Dienst: ${_duration(row['summary']['duty_ms'] as int)} · Pauze: ${_duration(row['summary']['pause_ms'] as int)}',
                ),
              ),
            ),
          if (!_busy && (_cursor != null || !_loaded || _error != null))
            TextButton(
              onPressed: _load,
              child: Text(
                _error != null ? 'Opnieuw proberen' : 'Meer diensten',
              ),
            ),
        ],
      ),
    );
  }
}
