import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'company_vehicle_duty_recovery_panel.dart';

class CompanyVehiclePairingClient {
  CompanyVehiclePairingClient({
    required this.baseUrl,
    required this.token,
    required this.tenantId,
    required this.companyId,
    required this.vehicleId,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String baseUrl, token, tenantId, companyId, vehicleId;
  final http.Client _client;
  void close() => _client.close();
  Future<Map<String, dynamic>> _deviceRequest(
    String action,
    Map<String, dynamic> extra, {
    bool duty = false,
  }) async {
    if ([token, companyId, vehicleId].any((value) => value.isEmpty))
      throw StateError('company_session_required');
    final response = await _client
        .post(
          Uri.parse(
            duty
                ? '$baseUrl/admin/company/vehicle-duty-$action'
                : '$baseUrl/admin/company/vehicle-device/$action',
          ),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            if (tenantId.isNotEmpty) 'tenant_id': tenantId,
            'company_id': companyId,
            'vehicle_id': vehicleId,
            ...extra,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final dynamic result = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        result is! Map<String, dynamic> ||
        result['ok'] != true) {
      if (duty)
        throw VehicleDutyRecoveryException(
          result is Map &&
                  result['error'] is String &&
                  RegExp(r'^[a-z_]{1,80}$').hasMatch(result['error'] as String)
              ? result['error'] as String
              : 'duty_recovery_unconfirmed',
        );
      throw StateError('device_operation_unconfirmed');
    }
    return result;
  }

  Future<Map<String, dynamic>> dutyState() async {
    final result = await _deviceRequest('state', {}, duty: true);
    if (result['vehicle_id'] != vehicleId ||
        result['version'] is! int ||
        result['duties'] is! List ||
        (result['duties'] as List).length > 1)
      throw const VehicleDutyRecoveryException('invalid_response');
    for (final row in result['duties'] as List) {
      if (row is! Map ||
          row['vehicle_id'] != vehicleId ||
          row['duty_id'] is! String ||
          row['driver_id'] is! String ||
          row['started_at_ms'] is! int ||
          row['ended_at_ms'] != null)
        throw const VehicleDutyRecoveryException('invalid_response');
    }
    return result;
  }

  Future<void> recoverDuty(Map<String, dynamic> command) async {
    final result = await _deviceRequest('recover', {
      for (final key in [
        'driver_id',
        'duty_id',
        'device_id',
        'expected_version',
        'command_id',
        'reason',
      ])
        key: command[key],
    }, duty: true);
    final duty = result['duty'];
    final recovery = duty is Map ? duty['recovery'] : null;
    if (result['version'] is! int ||
        duty is! Map ||
        duty['duty_id'] != command['duty_id'] ||
        duty['driver_id'] != command['driver_id'] ||
        duty['vehicle_id'] != vehicleId ||
        duty['ended_at_ms'] is! int ||
        recovery is! Map ||
        recovery['role'] != 'company_admin' ||
        recovery['reason'] != command['reason'] ||
        recovery['device_id'] != command['device_id'])
      throw const VehicleDutyRecoveryException('invalid_response');
  }

  Future<Map<String, dynamic>> devices({String? cursor}) async {
    final result = await _deviceRequest('list', {
      if (cursor != null) 'cursor': cursor,
    });
    if (result['vehicle_id'] != vehicleId ||
        result['items'] is! List ||
        result['cursor'] != null && result['cursor'] is! String)
      throw StateError('device_inventory_invalid');
    final items = <Map<String, dynamic>>[];
    for (final dynamic row in result['items'] as List) {
      if (row is! Map ||
          row['vehicle_id'] != vehicleId ||
          row['device_id'] is! String ||
          !RegExp(
            r'^[a-zA-Z0-9_.-]{1,96}$',
          ).hasMatch(row['device_id'] as String) ||
          row['expires_at_ms'] is! int ||
          row['revoked'] is! bool ||
          !['paired', 'revoked', 'expired'].contains(row['status']))
        throw StateError('device_inventory_invalid');
      items.add({
        for (final key in [
          'device_id',
          'vehicle_id',
          'expires_at_ms',
          'revoked',
          'status',
        ])
          key: row[key],
      });
    }
    return {'items': items, 'cursor': result['cursor']};
  }

  Future<void> revoke(String deviceId) async {
    if (!RegExp(r'^[a-zA-Z0-9_.-]{1,96}$').hasMatch(deviceId))
      throw StateError('device_id_invalid');
    await _deviceRequest('revoke', {'device_id': deviceId});
  }

  Future<Map<String,dynamic>> authorizeTransition(String deviceId,String operation,{String? targetVehicle}) async {
    final result=await _deviceRequest('create-transition',{'device_id':deviceId,'operation':operation,
      if(operation=='switch')'vehicle_id':targetVehicle});
    final qr=result['qr_payload'];
    if(qr is! Map || qr['kind']!='fluxidi_vehicle_device_transition' || qr['version']!=1 ||
      qr['operation']!=operation || qr['company_id']!=companyId || qr['device_id']!=deviceId ||
      qr['tenant_id'] is! String || tenantId.isNotEmpty && qr['tenant_id']!=tenantId ||
      qr['challenge_id'] is! String || qr['pairing_token'] is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(qr['pairing_token'] as String) || result['expires_at_ms'] is! int || result['expires_at_ms'] <= DateTime.now().millisecondsSinceEpoch ||
      operation=='switch' && qr['vehicle_id']!=targetVehicle) throw StateError('device_transition_grant_invalid');
    return {'ok':true,'expires_at_ms':result['expires_at_ms'],'qr_payload':{for(final key in ['kind','version','tenant_id','company_id','device_id','operation','vehicle_id','challenge_id','pairing_token'])key:qr[key]}};
  }

  Future<Map<String, dynamic>> create() async {
    if ([token, companyId, vehicleId].any((value) => value.isEmpty))
      throw StateError('company_session_required');
    final response = await _client
        .post(
          Uri.parse('$baseUrl/admin/company/vehicle-device/create'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            if (tenantId.isNotEmpty) 'tenant_id': tenantId,
            'company_id': companyId,
            'vehicle_id': vehicleId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final dynamic result = jsonDecode(response.body);
    final dynamic qr = result is Map ? result['qr_payload'] : null;
    if (response.statusCode != 200 ||
        result is! Map ||
        result['ok'] != true ||
        result['vehicle_id'] != vehicleId ||
        result['expires_at_ms'] is! int ||
        qr is! Map ||
        qr['kind'] != 'fluxidi_vehicle_device' ||
        qr['version'] != 1 ||
        qr['tenant_id'] is! String ||
        (qr['tenant_id'] as String).isEmpty ||
        (tenantId.isNotEmpty && qr['tenant_id'] != tenantId) ||
        qr['company_id'] != companyId ||
        qr['challenge_id'] is! String ||
        qr['pairing_token'] is! String ||
        (qr['pairing_token'] as String).length != 64)
      throw StateError('pairing_not_confirmed');
    // Only the documented payload enters the QR. No supplied URL/admin token.
    return {
      'expires_at_ms': result['expires_at_ms'],
      'qr_payload': {
        for (final key in [
          'kind',
          'version',
          'tenant_id',
          'company_id',
          'challenge_id',
          'pairing_token',
        ])
          key: qr[key],
      },
    };
  }
}

class CompanyVehiclePairingPage extends StatefulWidget {
  const CompanyVehiclePairingPage({
    super.key,
    required this.client,
    required this.vehicleLabel,
    this.language = 'nl',
    this.targetVehicles = const {},
  });
  final CompanyVehiclePairingClient client;
  final String vehicleLabel, language;
  final Map<String,String> targetVehicles;
  @override
  State<CompanyVehiclePairingPage> createState() =>
      _CompanyVehiclePairingPageState();
}

class _CompanyVehiclePairingPageState extends State<CompanyVehiclePairingPage> {
  String actionText(String action) => switch(widget.language) {
    'en'=>action=='switch'?'Authorize vehicle switch':'Authorize device unlink',
    'fr'=>action=='switch'?'Autoriser le changement de véhicule':'Autoriser la dissociation',
    'es'=>action=='switch'?'Autorizar cambio de vehículo':'Autorizar desvinculación',
    'de'=>action=='switch'?'Fahrzeugwechsel autorisieren':'Gerätetrennung autorisieren',
    _=>action=='switch'?'Voertuigwissel toestaan':'Toestelontkoppeling toestaan',
  };
  String get qrInstructions {
    final operation = _result?['qr_payload']?['operation'];
    if (operation == 'switch' || operation == 'unlink') {
      return switch (widget.language) {
        'en' => 'Scan this single-use authorization on the linked driver device using the matching action below. This is not a customer booking QR.',
        'fr' => 'Scannez cette autorisation unique sur l’appareil chauffeur lié avec l’action correspondante. Ce n’est pas un QR de réservation client.',
        'es' => 'Escanea esta autorización de un solo uso en el dispositivo vinculado con la acción correspondiente. No es un QR de reserva de clientes.',
        'de' => 'Diese einmalige Freigabe am verknüpften Fahrergerät mit der passenden Aktion scannen. Dies ist kein Kundenbuchungs-QR.',
        _ => 'Scan deze eenmalige toestemming op het gekoppelde chauffeurtoestel via de overeenkomstige actie. Dit is geen klantenboekings-QR.',
      };
    }
    return switch (widget.language) {
      'en' => 'Create a vehicle code for the first device link. For a switch or unlink, use the three-dot menu beside a paired device. These codes are not customer booking QRs.',
      'fr' => 'Créez un code véhicule pour la première liaison. Pour changer ou dissocier, utilisez le menu à trois points de l’appareil lié. Ces codes ne sont pas des QR de réservation client.',
      'es' => 'Crea un código de vehículo para la primera vinculación. Para cambiar o desvincular, usa el menú de tres puntos del dispositivo vinculado. No son QR de reserva de clientes.',
      'de' => 'Für die erste Geräteverknüpfung einen Fahrzeugcode erstellen. Zum Wechseln oder Trennen das Dreipunktmenü am verknüpften Gerät verwenden. Dies sind keine Kundenbuchungs-QRs.',
      _ => 'Maak een voertuigcode voor een eerste toestelkoppeling. Gebruik voor wisselen of ontkoppelen het driestippenmenu bij een gekoppeld toestel. Deze codes zijn geen klantenboekings-QR’s.',
    };
  }
  Future<void> _authorize(Map<String,dynamic> device,String action) async {
    String? target;
    if(action=='switch') {
      target=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:Text(actionText(action)),children:[
        for(final entry in widget.targetVehicles.entries.where((e)=>e.key!=widget.client.vehicleId))
          SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,entry.key),child:Text(entry.value)),
      ]));
      if(target==null || !mounted)return;
    }
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(actionText(action)),
      content:Text('${widget.vehicleLabel}\n${device['device_id']}\n${target==null?'':widget.targetVehicles[target]}'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(MaterialLocalizations.of(ctx).okButtonLabel))]));
    if(confirmed!=true || !mounted)return;
    setState(()=>_busy=true);
    try {
      final result=await widget.client.authorizeTransition(device['device_id'] as String,action,targetVehicle:target);
      if(mounted)setState(() { _result=result;_error=null; });
    } catch(_) { if(mounted)setState(()=>_error=widget.language=='de'?'Autorisierung nicht bestätigt.':text('Autorisatie niet bevestigd.','Authorization not confirmed.','Autorisation non confirmée.','Autorización sin confirmar.')); }
    finally { if(mounted)setState(()=>_busy=false); }
  }
  Map<String, dynamic>? _result;
  Timer? _timer;
  bool _busy = false;
  String? _error;
  String? _deviceError, _deviceCursor;
  bool _devicesBusy = true;
  final List<Map<String, dynamic>> _devices = [];
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
    _loadDevices();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _result != null) setState(() {});
    });
  }

  Future<void> _loadDevices({bool more = false}) async {
    setState(() {
      _devicesBusy = true;
      _deviceError = null;
    });
    try {
      final result = await widget.client.devices(
        cursor: more ? _deviceCursor : null,
      );
      if (!mounted) return;
      if (more && result['cursor'] != null && result['cursor'] == _deviceCursor)
        throw StateError('device_cursor_not_advancing');
      final rows = [
        if (more) ..._devices,
        ...(result['items'] as List).cast<Map<String, dynamic>>(),
      ];
      if (rows.map((row) => row['device_id']).toSet().length != rows.length)
        throw StateError('device_inventory_duplicate');
      setState(() {
        _devices
          ..clear()
          ..addAll(rows);
        _deviceCursor = result['cursor'] as String?;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _deviceError = text(
            'Toestellen konden niet worden geladen.',
            'Could not load devices.',
            'Impossible de charger les appareils.',
            'No se pudieron cargar los dispositivos.',
          ),
        );
    } finally {
      if (mounted) setState(() => _devicesBusy = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          text(
            'Toestel ontkoppelen?',
            'Unpair device?',
            'Délier l’appareil ?',
            '¿Desvincular dispositivo?',
          ),
        ),
        content: Text(
          text(
            'Dit toestel kan daarna geen nieuwe aanvragen ontvangen of accepteren. Voor hergebruik is een nieuwe voertuigcode nodig.',
            'This device can no longer receive or accept new requests. A new vehicle code is required to use it again.',
            'Cet appareil ne pourra plus recevoir ni accepter de demandes. Un nouveau code véhicule sera nécessaire.',
            'El dispositivo no podrá recibir ni aceptar solicitudes. Necesitará un nuevo código del vehículo.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(text('Annuleren', 'Cancel', 'Annuler', 'Cancelar')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(text('Ontkoppelen', 'Unpair', 'Délier', 'Desvincular')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _deviceError = null;
    });
    try {
      await widget.client.revoke(device['device_id'] as String);
      await _loadDevices();
    } catch (_) {
      if (mounted)
        setState(
          () => _deviceError = text(
            'Ontkoppeling niet bevestigd. Vernieuw en probeer opnieuw.',
            'Unpairing unconfirmed. Refresh and retry.',
            'Déliaison non confirmée. Actualisez et réessayez.',
            'Desvinculación sin confirmar. Actualiza y reintenta.',
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.client.create();
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = text(
            'Koppeling niet bevestigd. Controleer de bedrijfsinstellingen en probeer opnieuw.',
            'Pairing unconfirmed. Check company settings and retry.',
            'Liaison non confirmée. Vérifiez les paramètres et réessayez.',
            'Vinculación sin confirmar. Revisa la configuración e inténtalo de nuevo.',
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        _result != null &&
        (_result!['expires_at_ms'] as int) >
            DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          text(
            'Toestel aan voertuig koppelen',
            'Pair vehicle device',
            'Lier un appareil au véhicule',
            'Vincular dispositivo al vehículo',
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              widget.vehicleLabel,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(qrInstructions, key: const ValueKey('device_qr_instructions')),
            if (valid) ...[
              if (_result?['qr_payload']?['operation'] is String) Text(actionText(_result!['qr_payload']['operation'] as String)),
              const SizedBox(height: 24),
              ColoredBox(
                color: Colors.white,
                child: QrImageView(
                  data: jsonEncode(_result!['qr_payload']),
                  size: 280,
                ),
              ),
              Text(
                text(
                  'Eenmalig bruikbaar · maximaal 5 minuten geldig',
                  'Single use · valid for up to 5 minutes',
                  'Usage unique · valable 5 minutes maximum',
                  'Un solo uso · válido hasta 5 minutos',
                ),
              ),
            ],
            if (_result != null && !valid)
              Text(
                text(
                  'Code verlopen. Maak een nieuwe code.',
                  'Code expired. Create a new code.',
                  'Code expiré. Créez un nouveau code.',
                  'Código caducado. Crea uno nuevo.',
                ),
              ),
            if (_error != null) Text(_error!),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.qr_code),
              label: Text(
                text(
                  'Nieuwe voertuigcode maken',
                  'Create vehicle code',
                  'Créer un code véhicule',
                  'Crear código del vehículo',
                ),
              ),
            ),
            if (_busy) const CircularProgressIndicator(),
            const Divider(height: 32),
            Text(
              text(
                'Gekoppelde toestellen',
                'Paired devices',
                'Appareils liés',
                'Dispositivos vinculados',
              ),
            ),
            Text(
              text(
                'Gekoppeld betekent niet dat de wagen online of beschikbaar is.',
                'Paired does not mean the vehicle is online or available.',
                'Lié ne signifie pas que le véhicule est en ligne ou disponible.',
                'Vinculado no significa que el vehículo esté conectado o disponible.',
              ),
            ),
            if (_devicesBusy) const LinearProgressIndicator(),
            CompanyVehicleDutyRecoveryPanel(
              key: ValueKey(widget.client.vehicleId),
              devices: _devices,
              loadState: widget.client.dutyState,
              recover: widget.client.recoverDuty,
              language: widget.language,
            ),
            if (_deviceError != null) Text(_deviceError!),
            for (final device in _devices)
              Card(
                child: ListTile(
                  title: Text(device['device_id'] as String),
                  subtitle: Text(switch (device['status']) {
                    'revoked' => text(
                      'Ontkoppeld',
                      'Unpaired',
                      'Délié',
                      'Desvinculado',
                    ),
                    'expired' => text(
                      'Verlopen',
                      'Expired',
                      'Expiré',
                      'Caducado',
                    ),
                    _ => text('Gekoppeld', 'Paired', 'Lié', 'Vinculado'),
                  }),
                  trailing: device['status'] == 'paired'
                      ? Row(mainAxisSize:MainAxisSize.min,children:[PopupMenuButton<String>(
                          enabled:!_busy && !_devicesBusy,
                          onSelected:(action)=>_authorize(device,action),
                          itemBuilder:(_)=>[for(final action in ['switch','unlink']) PopupMenuItem(value:action,child:Text(actionText(action)))]),IconButton(
                          icon: const Icon(Icons.link_off),
                          tooltip: text(
                            'Ontkoppelen',
                            'Unpair',
                            'Délier',
                            'Desvincular',
                          ),
                          onPressed: _busy || _devicesBusy
                              ? null
                              : () => _revoke(device),
                        )])
                      : null,
                ),
              ),
            TextButton(
              onPressed: _busy || _devicesBusy ? null : () => _loadDevices(),
              child: Text(
                text(
                  'Toestellen vernieuwen',
                  'Refresh devices',
                  'Actualiser les appareils',
                  'Actualizar dispositivos',
                ),
              ),
            ),
            if (_deviceCursor != null)
              TextButton(
                onPressed: _busy || _devicesBusy
                    ? null
                    : () => _loadDevices(more: true),
                child: Text(
                  text(
                    'Meer toestellen',
                    'More devices',
                    'Plus d’appareils',
                    'Más dispositivos',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
