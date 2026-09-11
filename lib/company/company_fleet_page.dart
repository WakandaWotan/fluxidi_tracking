// COMPANY-CUSTOMER-OPS-P0 — existing /admin/fleet/vehicles admin on Windows.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';

const Key kCompanyFleetPageKey = Key('company_fleet_page');
const Key kCompanyFleetAddKey = Key('company_fleet_add');
const Key kCompanyFleetNameKey = Key('company_fleet_name');
const Key kCompanyFleetPlateKey = Key('company_fleet_plate');

class CompanyFleetPage extends StatefulWidget {
  const CompanyFleetPage({
    super.key,
    this.language,
    this.vehiclesLoader,
    this.subscriptionLoader,
    this.vehiclesSaver,
  });

  final AppLanguage? language;
  final Future<List<Map<String, dynamic>>> Function()? vehiclesLoader;
  final Future<Map<String, dynamic>> Function()? subscriptionLoader;
  final Future<List<Map<String, dynamic>>> Function(
    List<Map<String, dynamic>> vehicles,
  )?
  vehiclesSaver;

  @override
  State<CompanyFleetPage> createState() => _CompanyFleetPageState();
}

class _CompanyFleetPageState extends State<CompanyFleetPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _vehicles = const <Map<String, dynamic>>[];
  int _maxVehicles = 1;
  final _name = TextEditingController();
  final _plate = TextEditingController();
  final _brand = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    _brand.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        (widget.vehiclesLoader ?? fetchCompanyOpsVehicles)(),
        (widget.subscriptionLoader ?? fetchCompanyOpsSubscriptionProfile)(),
      ]);
      if (!mounted) return;
      setState(() {
        _vehicles = results[0] as List<Map<String, dynamic>>;
        _maxVehicles = companyOpsMaxVehicles(
          results[1] as Map<String, dynamic>,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Voertuigen laden mislukt.';
        _loading = false;
      });
    }
  }

  bool get _atCapacity => _vehicles.length >= _maxVehicles && _maxVehicles > 0;

  Future<void> _add() async {
    if (_atCapacity) {
      setState(() {
        _error =
            'Voertuiglimiet $_maxVehicles bereikt. Extra voertuig loopt via het bestaande abonnement; die aankoop is hier niet geopend.';
      });
      return;
    }
    final name = _name.text.trim();
    final plate = _plate.text.trim();
    if (name.isEmpty || plate.isEmpty) {
      setState(() => _error = 'Naam en nummerplaat zijn verplicht.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final scope = companyOpsScope();
      final next = <Map<String, dynamic>>[
        ..._vehicles,
        <String, dynamic>{
          'vehicle_id': 'vh_${DateTime.now().millisecondsSinceEpoch}',
          'vehicle_name': name,
          'brand_model': _brand.text.trim(),
          'license_plate': plate,
          'is_active': true,
          ...scope,
        },
      ];
      final saved = await (widget.vehiclesSaver ?? saveCompanyOpsVehicles)(
        next,
      );
      if (!mounted) return;
      setState(() {
        _vehicles = saved;
        _name.clear();
        _plate.clear();
        _brand.clear();
        _saving = false;
      });
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Voertuig bewaren mislukt.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanyFleetPageKey,
        appBar: AppBar(title: const Text('Voertuigen')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Limiet: $_maxVehicles  •  Nu: ${_vehicles.length}'),
                  const SizedBox(height: 8),
                  if (_vehicles.isEmpty)
                    const Text('Nog geen voertuigen voor dit bedrijf.')
                  else
                    for (final vehicle in _vehicles)
                      Card(
                        child: ListTile(
                          title: Text(
                            (vehicle['vehicle_name'] ??
                                    vehicle['vehicleName'] ??
                                    vehicle['vehicle_id'] ??
                                    '')
                                .toString(),
                          ),
                          subtitle: Text(
                            [
                              vehicle['brand_model'] ?? vehicle['brandModel'] ?? '',
                              vehicle['license_plate'] ??
                                  vehicle['licensePlate'] ??
                                  '',
                            ].where((part) => part.toString().trim().isNotEmpty).join(' • '),
                          ),
                        ),
                      ),
                  const SizedBox(height: 16),
                  TextField(
                    key: kCompanyFleetNameKey,
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Voertuignaam'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _brand,
                    decoration: const InputDecoration(labelText: 'Merk / model'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: kCompanyFleetPlateKey,
                    controller: _plate,
                    decoration: const InputDecoration(labelText: 'Nummerplaat'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    key: kCompanyFleetAddKey,
                    onPressed: _saving || _atCapacity ? null : _add,
                    child: Text(
                      _atCapacity
                          ? 'Limiet bereikt'
                          : _saving
                          ? 'Bewaren…'
                          : 'Voertuig toevoegen',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'De serverlimiet wordt niet omzeild. Extra voertuig via abonnement blijft de bestaande betaalroute en is hier niet gestart.',
                  ),
                ],
              ),
      ),
    );
  }
}
