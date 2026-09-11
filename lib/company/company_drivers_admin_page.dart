// COMPANY-CUSTOMER-OPS-P0 — administrative drivers index, not the cockpit.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';

const Key kCompanyDriversAdminPageKey = Key('company_drivers_admin_page');
const Key kCompanyDriversAddKey = Key('company_drivers_add');
const Key kCompanyDriversNameKey = Key('company_drivers_name');
const Key kCompanyDriversPhoneKey = Key('company_drivers_phone');

class CompanyDriversAdminPage extends StatefulWidget {
  const CompanyDriversAdminPage({
    super.key,
    this.language,
    this.driversLoader,
    this.subscriptionLoader,
    this.driverUpsert,
    this.driverDelete,
  });

  final AppLanguage? language;
  final Future<List<Map<String, dynamic>>> Function()? driversLoader;
  final Future<Map<String, dynamic>> Function()? subscriptionLoader;
  final Future<void> Function(Map<String, dynamic> driver)? driverUpsert;
  final Future<void> Function(String driverId)? driverDelete;

  @override
  State<CompanyDriversAdminPage> createState() =>
      _CompanyDriversAdminPageState();
}

class _CompanyDriversAdminPageState extends State<CompanyDriversAdminPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _drivers = const <Map<String, dynamic>>[];
  int _maxDrivers = 1;
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        (widget.driversLoader ?? fetchCompanyOpsDrivers)(),
        (widget.subscriptionLoader ?? fetchCompanyOpsSubscriptionProfile)(),
      ]);
      if (!mounted) return;
      setState(() {
        _drivers = results[0] as List<Map<String, dynamic>>;
        _maxDrivers = companyOpsMaxDrivers(results[1] as Map<String, dynamic>);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Chauffeurs laden mislukt.';
        _loading = false;
      });
    }
  }

  bool get _atCapacity => _drivers.length >= _maxDrivers && _maxDrivers > 0;

  Future<void> _add() async {
    if (_atCapacity) {
      setState(() {
        _error = 'Chauffeurslimiet $_maxDrivers bereikt.';
      });
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Naam is verplicht.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.driverUpsert ?? upsertCompanyOpsDriver)(<String, dynamic>{
        'driver_id': 'drv_${DateTime.now().millisecondsSinceEpoch}',
        'display_name': name,
        'phone': _phone.text.trim(),
        'is_active': true,
      });
      _name.clear();
      _phone.clear();
      if (mounted) setState(() => _saving = false);
      await _load();
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Chauffeur bewaren mislukt.';
        _saving = false;
      });
    }
  }

  Future<void> _delete(String driverId) async {
    setState(() => _saving = true);
    try {
      await (widget.driverDelete ?? deleteCompanyOpsDriver)(driverId);
      if (mounted) setState(() => _saving = false);
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Verwijderen mislukt.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanyDriversAdminPageKey,
        appBar: AppBar(title: const Text('Chauffeurs')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Limiet: $_maxDrivers  •  Nu: ${_drivers.length}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Dit is administratief chauffeursbeheer. De rijcockpit, kaart en navigatie blijven native.',
                  ),
                  const SizedBox(height: 12),
                  if (_drivers.isEmpty)
                    const Text('Nog geen chauffeurs voor dit bedrijf.')
                  else
                    for (final driver in _drivers)
                      Card(
                        child: ListTile(
                          title: Text(
                            (driver['display_name'] ??
                                    driver['displayName'] ??
                                    driver['driver_id'] ??
                                    '')
                                .toString(),
                          ),
                          subtitle: Text(
                            (driver['phone'] ?? '').toString(),
                          ),
                          trailing: IconButton(
                            onPressed: _saving
                                ? null
                                : () => _delete(
                                    (driver['driver_id'] ?? '').toString(),
                                  ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                  const SizedBox(height: 16),
                  TextField(
                    key: kCompanyDriversNameKey,
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Naam'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: kCompanyDriversPhoneKey,
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefoon (+landcode)',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    key: kCompanyDriversAddKey,
                    onPressed: _saving || _atCapacity ? null : _add,
                    child: Text(
                      _atCapacity
                          ? 'Limiet bereikt'
                          : _saving
                          ? 'Bewaren…'
                          : 'Chauffeur toevoegen',
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
