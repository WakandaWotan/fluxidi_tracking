import 'dart:math';
import 'package:flutter/material.dart';
import 'driver_management_native_repository.dart';
import 'driver_management_theme.dart';

/// Flutter presentation of the recovered partners.js directory and exact DTO.
/// Membership, revision, CSRF and financial guards remain on the existing host.
class DriverManagementPartners extends StatefulWidget {
  const DriverManagementPartners({super.key, required this.repository});
  final DriverManagementNativeRepository repository;
  @override
  State<DriverManagementPartners> createState() =>
      DriverManagementPartnersState();
}

class DriverManagementPartnersState extends State<DriverManagementPartners> {
  Future<void> refresh() => _load();
  bool goBack() {
    if (_draft != null) {
      setState(() => _draft = null);
      return true;
    }
    if (_selected != null) {
      setState(() => _selected = null);
      return true;
    }
    return false;
  }

  static const relationships = {
    'individual_subcontractor': 'Zelfstandige chauffeur',
    'subcontractor_company': 'Onderaannemersbedrijf',
    'partner_company': 'Partnerbedrijf',
  };
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _records;
  Map<String, dynamic>? _selected, _draft;
  final _name = TextEditingController(), _contact = TextEditingController();
  String _status = '', _section = 'overview', _membership = '';
  String? _error;
  bool _busy = true;
  int _page = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DriverManagementPartners oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _records = null;
      _selected = null;
      _draft = null;
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = widget.repository;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final records = await repo.partners();
      if (!mounted || repo != widget.repository) return;
      setState(() {
        _records = records;
        _busy = false;
      });
    } catch (e) {
      if (mounted && repo == widget.repository)
        setState(() {
          _error = _message(e);
          _busy = false;
          _records = null;
        });
    }
  }

  String _message(Object e) => e is DriverManagementReadFailure
      ? e.message
      : 'De partnergegevens konden niet veilig worden geladen.';
  List<String> _ids(Map<String, dynamic> p, String field) =>
      List<String>.from(p[field] as List? ?? const []);
  String _text(dynamic value) => value is String && value.trim().isNotEmpty
      ? value
      : 'Nog niet beschikbaar';
  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: child,
  );
  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final longest = text
            .split(' ')
            .reduce((a, b) => a.length >= b.length ? a : b);
        final style = DefaultTextStyle.of(
          context,
        ).style.copyWith(fontSize: 22, fontWeight: FontWeight.w700);
        final painter = TextPainter(
          text: TextSpan(text: longest, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        var font = 22.0;
        while (painter.width > constraints.maxWidth - 2 && font > 12) {
          font -= 0.25;
          painter.text = TextSpan(
            text: longest,
            style: style.copyWith(fontSize: font),
          );
          painter.layout();
        }
        painter.dispose();
        return Text(text, style: style.copyWith(fontSize: font));
      },
    ),
  );
  Widget _field(String label, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(text),
      ],
    ),
  );
  Widget _metric(IconData icon, String value, String label) => Container(
    key: ValueKey('partner-metric-$label'),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          softWrap: true,
          style: const TextStyle(fontSize: 11.5, height: 1.2),
        ),
        if (value == '—')
          driverManagementReadableText(
            'Nog niet beschikbaar',
            style: const TextStyle(fontSize: 10.5, height: 1.2),
          ),
      ],
    ),
  );
  Widget _stats() => LayoutBuilder(
    builder: (context, c) {
      final records = _records!;
      final metrics = [
        (Icons.apartment, '${records.length}', 'Partners'),
        (
          Icons.people_outline,
          '${records.expand((p) => _ids(p, 'driver_ids')).toSet().length}',
          'Gekoppelde chauffeurs',
        ),
        (
          Icons.directions_car_outlined,
          '${records.expand((p) => _ids(p, 'vehicle_ids')).toSet().length}',
          'Gekoppelde voertuigen',
        ),
        (Icons.route_outlined, '—', 'Ritten deze maand'),
      ];
      final n =
          c.maxWidth < 250 || MediaQuery.textScalerOf(context).scale(1) > 1.8
          ? 1
          : c.maxWidth >= 850
          ? 4
          : 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final m in metrics)
            SizedBox(
              width: (c.maxWidth - 10 * (n - 1)) / n,
              child: _metric(m.$1, m.$2, m.$3),
            ),
        ],
      );
    },
  );
  void _edit([Map<String, dynamic>? p]) {
    if (!widget.repository.partnerWrite) return;
    final random = Random.secure();
    setState(() {
      _draft = p == null
          ? {
              'id':
                  'partner-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
              'business_name': '',
              'contact_person': '',
              'relationship_type': 'partner_company',
              'status': 'active',
              'driver_ids': <String>[],
              'vehicle_ids': <String>[],
              'revision': 0,
              'rule_id': null,
              'rule_version': null,
            }
          : {
              ...p,
              'driver_ids': _ids(p, 'driver_ids'),
              'vehicle_ids': _ids(p, 'vehicle_ids'),
            };
      _name.text = _draft!['business_name'] as String;
      _contact.text = _draft!['contact_person'] as String? ?? '';
      _error = null;
    });
  }

  Future<void> _pick(String kind) async {
    final draft = _draft, repo = widget.repository;
    if (draft == null) return;
    try {
      await repo.assertSession();
      final items = kind == 'driver'
          ? await repo.driverOptions()
          : repo.vehicles;
      if (!mounted || draft != _draft || repo != widget.repository) return;
      final selected = _ids(draft, '${kind}_ids').toSet();
      final query = TextEditingController();
      final result = await showDialog<Set<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) {
            final matches = items
                .where(
                  (d) =>
                      [d['display_name'], d['vehicle_name'], d['license_plate']]
                          .join(' ')
                          .toLowerCase()
                          .contains(query.text.trim().toLowerCase()),
                )
                .toList();
            return AlertDialog(
              title: Text(
                kind == 'driver'
                    ? 'Chauffeurs koppelen'
                    : 'Voertuigen koppelen',
              ),
              content: SizedBox(
                width: 520,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      key: const ValueKey('partner-member-search'),
                      controller: query,
                      onChanged: (_) => update(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Zoeken',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${selected.length} geselecteerd'),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final item in matches)
                            CheckboxListTile(
                              value: selected.contains(item['${kind}_id']),
                              title: Text(
                                _text(
                                  kind == 'driver'
                                      ? item['display_name']
                                      : item['vehicle_name'],
                                ),
                              ),
                              subtitle: Text(
                                kind == 'driver'
                                    ? _text(item['status'])
                                    : _text(item['license_plate']),
                              ),
                              onChanged: (value) => update(() {
                                final id = item['${kind}_id'] as String;
                                if (value == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              }),
                            ),
                          if (matches.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Geen resultaten binnen je bedrijf.'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuleren'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const Text('Selectie gebruiken'),
                ),
              ],
            );
          },
        ),
      );
      // The dialog may still use its controller during the exit animation.
      Future<void>.delayed(const Duration(seconds: 1), query.dispose);
      await repo.assertSession();
      if (mounted &&
          result != null &&
          draft == _draft &&
          repo == widget.repository)
        setState(() => draft['${kind}_ids'] = result.toList());
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  Future<void> _save() async {
    final draft = _draft, repo = widget.repository;
    if (draft == null || _busy) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Vul de bedrijfsnaam in.');
      return;
    }
    if (_records!.any(
      (p) =>
          p['id'] != draft['id'] &&
          (p['business_name'] as String).trim().toLowerCase() ==
              name.toLowerCase(),
    )) {
      setState(
        () => _error =
            'Deze partnernaam bestaat al. Open de bestaande samenwerking om dubbele registratie te voorkomen.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Partnergegevens opslaan?'),
        content: Text(
          '$name\n${_ids(draft, 'driver_ids').length} chauffeurs · ${_ids(draft, 'vehicle_ids').length} voertuigen\n\nDe bestaande koppelingen worden vervangen door je selectie. Er wordt geen eigenaarschap overgedragen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Terug'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bevestigen en opslaan'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        draft != _draft ||
        repo != widget.repository)
      return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await repo.savePartner({
        'id': draft['id'],
        'business_name': name,
        'contact_person': _contact.text.trim(),
        'relationship_type': draft['relationship_type'],
        'status': draft['status'],
        'expected_revision': draft['revision'],
        'driver_ids': draft['driver_ids'],
        'vehicle_ids': draft['vehicle_ids'],
        'rule_id': draft['rule_id'],
        'rule_version': draft['rule_version'],
      });
      if (!mounted || repo != widget.repository) return;
      setState(() {
        _records = [..._records!.where((p) => p['id'] != saved['id']), saved];
        _selected = saved;
        _draft = null;
        _section = 'overview';
        _busy = false;
      });
    } catch (e) {
      if (mounted && repo == widget.repository)
        setState(() {
          _error = _message(e);
          _busy = false;
        });
    }
  }

  Widget _editor() {
    final draft = _draft!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _draft = null),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Partnerbedrijven'),
        ),
        _title(
          draft['revision'] == 0
              ? 'Partnerbedrijf toevoegen'
              : 'Partner bewerken',
        ),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Bedrijfsgegevens',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('partner-business-name'),
                controller: _name,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Bedrijfsnaam *',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contact,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Contactpersoon',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Telefoon, e-mail en logo zijn nog niet gekoppeld aan deze partnerregistratie.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Relatie',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (!relationships.containsKey(draft['relationship_type']))
                _field(
                  'Bestaande relatie',
                  draft['relationship_type'] == 'employee'
                      ? 'Werknemer — behouden'
                      : 'Bestaande relatie — behouden',
                ),
              if (relationships.containsKey(draft['relationship_type']))
                for (final e in relationships.entries)
                  RadioListTile<String>(
                    title: Text(e.value),
                    subtitle: Text(
                      {
                        'individual_subcontractor': 'Werkt voor eigen rekening',
                        'subcontractor_company':
                            'Eigen chauffeurs en voertuigen',
                        'partner_company':
                            'Samenwerken met een ander taxibedrijf',
                      }[e.key]!,
                    ),
                    value: e.key,
                    groupValue: draft['relationship_type'] as String,
                    onChanged: (v) =>
                        setState(() => draft['relationship_type'] = v),
                  ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: draft['status'] as String,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Actief')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactief')),
                ],
                onChanged: (v) => setState(() => draft['status'] = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chauffeurs en voertuigen',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Koppel uitsluitend gegevens waarvoor je bedrijf toegang heeft. Gegevens van een ander Fluxidi-bedrijf vereisen een goedgekeurde bedrijfsrelatie; het eigenaarschap blijft bij dat bedrijf.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('partner-pick-drivers'),
                onPressed: () => _pick('driver'),
                icon: const Icon(Icons.people_outline),
                label: Text(
                  'Chauffeurs koppelen (${_ids(draft, 'driver_ids').length})',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pick('vehicle'),
                icon: const Icon(Icons.directions_car_outlined),
                label: Text(
                  'Voertuigen koppelen (${_ids(draft, 'vehicle_ids').length})',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Commissie', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text(
                'Nog niet beschikbaar. Bestaande financiële koppelingen blijven ongewijzigd.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => setState(() => _draft = null),
              child: const Text('Annuleren'),
            ),
            FilledButton.icon(
              key: const ValueKey('partner-save'),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Opslaan'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openPartnerDrivers(Map<String, dynamic> p) async {
    final repo = widget.repository;
    try {
      final ids = _ids(p, 'driver_ids');
      final data = await Future.wait(ids.map(repo.detail));
      if (!mounted || repo != widget.repository || _selected?['id'] != p['id'])
        return;
      setState(() {
        _memberDrivers = data;
        _section = 'drivers';
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  List<Map<String, dynamic>> _memberDrivers = [];
  Widget _detail() {
    final p = _selected!;
    final vehicles = widget.repository.vehicles
        .where((v) => _ids(p, 'vehicle_ids').contains(v['vehicle_id']))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _selected = null),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Partnerbedrijven'),
        ),
        _title(p['business_name'] as String),
        Text(p['status'] == 'active' ? 'Actief' : 'Inactief'),
        const SizedBox(height: 12),
        if (widget.repository.partnerWrite)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _edit(p),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Bewerken'),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final e in {
                'overview': 'Overzicht',
                'drivers': 'Chauffeurs',
                'vehicles': 'Voertuigen',
                'rides': 'Ritten',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _section == e.key,
                    onSelected: (_) {
                      if (e.key == 'drivers') {
                        _openPartnerDrivers(p);
                      } else {
                        setState(() => _section = e.key);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_section == 'overview')
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field('Contactpersoon', _text(p['contact_person'])),
                _field(
                  'Relatie',
                  relationships[p['relationship_type']] ??
                      (p['relationship_type'] == 'employee'
                          ? 'Werknemer'
                          : 'Bestaande relatie'),
                ),
                _field(
                  'Gekoppelde chauffeurs',
                  '${_ids(p, 'driver_ids').length}',
                ),
                _field(
                  'Gekoppelde voertuigen',
                  '${_ids(p, 'vehicle_ids').length}',
                ),
              ],
            ),
          ),
        if (_section == 'drivers')
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in _memberDrivers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_text(d['display_name'])),
                    subtitle: Text(_text(d['status'])),
                  ),
                if (_memberDrivers.isEmpty)
                  const Text('Nog geen chauffeurs gekoppeld aan deze partner.'),
              ],
            ),
          ),
        if (_section == 'vehicles')
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final v in vehicles)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_text(v['vehicle_name'])),
                    subtitle: Text(_text(v['license_plate'])),
                  ),
                if (vehicles.isEmpty)
                  const Text(
                    'Nog geen voertuiggegevens beschikbaar voor deze partner.',
                  ),
              ],
            ),
          ),
        if (_section == 'rides')
          _panel(
            const Text(
              'Ritten en bedragen voor deze partner: Nog niet beschikbaar.',
            ),
          ),
      ],
    );
  }

  Widget _overview() {
    final q = _search.text.trim().toLowerCase();
    final matches = _records!
        .where(
          (p) =>
              (_status.isEmpty || p['status'] == _status) &&
              (_membership.isEmpty || _ids(p, _membership).isNotEmpty) &&
              [
                p['business_name'],
                p['contact_person'],
                (p['service_area'] as Map?)?['name'],
              ].join(' ').toLowerCase().contains(q),
        )
        .toList();
    final pages = max(1, (matches.length / 12).ceil());
    _page = min(_page, pages - 1);
    final visible = matches.skip(_page * 12).take(12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Partnerbedrijven'),
        const Text('Je samenwerkingen, chauffeurs en voertuigen op één plek.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('partner-add'),
          onPressed: widget.repository.partnerWrite ? () => _edit() : null,
          icon: const Icon(Icons.add),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          ),
          label: const Text('Partnerbedrijf toevoegen'),
        ),
        if (!widget.repository.partnerWrite)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Je bedrijfsrechten geven alleen leestoegang.'),
          ),
        const SizedBox(height: 16),
        _stats(),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('partner-search'),
          controller: _search,
          onChanged: (_) => setState(() => _page = 0),
          decoration: const InputDecoration(
            hintText: 'Zoek partner…',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final e in const {
                '': 'Alle',
                'driver_ids': 'Met chauffeurs',
                'vehicle_ids': 'Met voertuigen',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _membership == e.key,
                    onSelected: (_) => setState(() {
                      _membership = e.key;
                      _page = 0;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _status,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Status'),
          items: const [
            DropdownMenuItem(value: '', child: Text('Alle statussen')),
            DropdownMenuItem(value: 'active', child: Text('Actief')),
            DropdownMenuItem(value: 'inactive', child: Text('Inactief')),
          ],
          onChanged: (v) => setState(() {
            _status = v ?? '';
            _page = 0;
          }),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Partnerbedrijven (${matches.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Vernieuwen'),
            ),
          ],
        ),
        if (matches.isEmpty)
          _panel(
            Column(
              children: [
                const Icon(Icons.apartment, size: 48),
                const SizedBox(height: 16),
                Text(
                  _records!.isEmpty
                      ? 'Nog geen partnerbedrijven'
                      : 'Geen partnerbedrijven gevonden',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Voeg een partner toe om chauffeurs, voertuigen en later ritten eenvoudig te beheren.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            final n = c.maxWidth >= 850 ? 2 : 1;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final p in visible)
                  SizedBox(
                    width: (c.maxWidth - 12 * (n - 1)) / n,
                    child: _panel(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.apartment),
                            title: Text(p['business_name'] as String),
                            subtitle: Text(
                              '${p['status'] == 'active' ? 'Actief' : 'Inactief'} · ${relationships[p['relationship_type']] ?? 'Bestaande relatie'}',
                            ),
                          ),
                          Text(
                            '${_ids(p, 'driver_ids').length} chauffeurs · ${_ids(p, 'vehicle_ids').length} voertuigen',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _selected = p;
                              _memberDrivers = [];
                              _section = 'overview';
                            }),
                            child: const Text('Openen'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (pages > 1)
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Pagina ${_page + 1} van $pages'),
              TextButton(
                onPressed: _page == 0 ? null : () => setState(() => _page--),
                child: const Text('Vorige'),
              ),
              TextButton(
                onPressed: _page + 1 >= pages
                    ? null
                    : () => setState(() => _page++),
                child: const Text('Volgende'),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('native-partners-page'),
    padding: const EdgeInsets.all(16),
    children: [
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!, key: const ValueKey('partner-error')),
                TextButton(
                  onPressed: _load,
                  child: const Text('Opnieuw proberen'),
                ),
              ],
            ),
          ),
        ),
      if (_records != null)
        if (_draft != null)
          _editor()
        else if (_selected != null)
          _detail()
        else
          _overview(),
    ],
  );
}
