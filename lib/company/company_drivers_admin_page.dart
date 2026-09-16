// COMPANY-CUSTOMER-OPS-P0 — administrative drivers index, not the cockpit.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color_chips.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule_page.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';

const Key kCompanyDriversRosterKey = Key('company_drivers_roster');

const Key kCompanyDriversAdminPageKey = Key('company_drivers_admin_page');
const Key kCompanyDriversAddKey = Key('company_drivers_add');
const Key kCompanyDriversNameKey = Key('company_drivers_name');
const Key kCompanyDriversPhoneKey = Key('company_drivers_phone');
const Key kCompanyDriversColorKey = Key('company_drivers_color');

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
  String _agendaColor = kCompanyDriverAgendaColorChoices.first;

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
      final drivers = await (widget.driversLoader ?? fetchCompanyOpsDrivers)();
      var maxDrivers = 1;
      try {
        final subscription =
            await (widget.subscriptionLoader ??
                fetchCompanyOpsSubscriptionProfile)();
        maxDrivers = companyOpsMaxDrivers(subscription);
      } catch (_) {
        // A failed cap request must not hide the loaded roster.
      }
      if (!mounted) return;
      setState(() {
        _drivers = drivers;
        _maxDrivers = maxDrivers;
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

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  bool get _atCapacity => _drivers.length >= _maxDrivers && _maxDrivers > 0;

  Widget _colorChoices({
    Key? key,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return KeyedSubtree(
      key: key,
      child: CompanyDriverAgendaColorChips(
        selected: selected,
        enabled: !_saving,
        onSelect: onSelect,
      ),
    );
  }

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
        'agenda_color': _agendaColor,
      });
      _name.clear();
      _phone.clear();
      notifyCompanyDriverAgendaColorsChanged();
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

  Future<void> _editRoster(Map<String, dynamic> driver) async {
    final driverId = companyAgendaDriverId(driver);
    if (driverId.isEmpty) return;
    final name = companyAgendaDriverName(driver);
    final loaded = await fetchCompanyOpsDriverSchedule(driverId);
    if (!mounted) return;
    final result = await openCompanyDriverSchedulePage(
      context,
      language: _lang,
      schedule:
          loaded.schedule ??
          CompanyDriverSchedule(
            driverId: driverId,
            timezone: kCompanyDefaultTimezone,
          ),
      driverName: name.isEmpty ? driverId : name,
      canEdit: companyDriverScheduleCallerCanEdit(
        isCompanyAdmin: true,
        callerDriverId: '',
        targetDriverId: driverId,
      ),
      persistenceAvailable: loaded.canPersist,
    );
    if (result == null || !loaded.canPersist) return;
    try {
      await saveCompanyOpsDriverSchedule(result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Uurrooster bewaren mislukt.');
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
                          leading: CircleAvatar(
                            backgroundColor: companyAgendaDriverLook(
                              driver,
                            ).color,
                            child: Text(
                              companyAgendaInitials(
                                companyAgendaDriverName(driver),
                              ),
                              style: TextStyle(
                                color: companyAgendaOnColor(
                                  companyAgendaDriverLook(driver).color,
                                ),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            (driver['display_name'] ??
                                    driver['displayName'] ??
                                    driver['driver_id'] ??
                                    '')
                                .toString(),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((driver['phone'] ?? '').toString()),
                              TextButton(
                                key: companyDriverAgendaColorActionKey(
                                  companyAgendaDriverId(driver),
                                ),
                                onPressed: _saving
                                    ? null
                                    : () async {
                                        final saved =
                                            await showCompanyDriverAgendaColorPicker(
                                              context: context,
                                              driver: driver,
                                              selected:
                                                  (driver['agenda_color'] ??
                                                          driver['agendaColor'] ??
                                                          '')
                                                      .toString(),
                                              language: _lang,
                                              companyDrivers: _drivers,
                                              driverUpsert: widget.driverUpsert,
                                            );
                                        if (saved && mounted) await _load();
                                      },
                                child: Text(
                                  kCompanyAgendaColorChange.of(_lang),
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: companyDriverScheduleActionKey(
                                  companyAgendaDriverId(driver),
                                ),
                                tooltip: kCompanyDriverScheduleTitle.of(_lang),
                                onPressed: _saving
                                    ? null
                                    : () => _editRoster(driver),
                                icon: const Icon(Icons.schedule_outlined),
                              ),
                              IconButton(
                                onPressed: _saving
                                    ? null
                                    : () => _delete(
                                        (driver['driver_id'] ?? '').toString(),
                                      ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
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
                  const SizedBox(height: 12),
                  Text(kCompanyAgendaColorLabel.of(_lang)),
                  const SizedBox(height: 6),
                  _colorChoices(
                    key: kCompanyDriversColorKey,
                    selected: _agendaColor,
                    onSelect: (color) => setState(() => _agendaColor = color),
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
