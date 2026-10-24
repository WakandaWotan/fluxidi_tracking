import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'company_timezone.dart';
import '../business_theme_palette.dart';
import 'driver_management_theme.dart';
import 'driver_management_native_repository.dart';
import 'driver_management_partners.dart';
import '../customer_app_header/customer_app_header_branding.dart';
import '../customer_app_header/header_local_cache.dart';

/// Flutter rendering of the recovered web/index.html, app.js and view.js.
/// The original server implementation remains the sole read authority.
class DriverManagementNativePage extends StatefulWidget {
  const DriverManagementNativePage({
    super.key,
    required this.connect,
    required this.session,
    required this.openLegacy,
    required this.manageDriver,
    this.recoverSession,
    this.shareCsv,
    this.palette,
    this.addDriver,
    this.globalAction,
    this.driverAction,
    this.openPartners,
    this.avatar,
    this.companyBranding,
    this.sessionKey,
  });

  final Future<DriverManagementNativeRepository> Function() connect;
  final ValueListenable<Object?> session;
  final VoidCallback openLegacy;
  final Future<void> Function(String) manageDriver;
  final Future<void> Function()? recoverSession;
  final Future<void> Function(String)? shareCsv;
  final BusinessThemePalette? palette;
  final Future<void> Function()? addDriver;
  final Future<void> Function(String)? globalAction;
  final Future<void> Function(String, String)? driverAction;
  final VoidCallback? openPartners;
  final Widget Function(String, double)? avatar;
  final CustomerAppHeaderBranding? companyBranding;
  final Object? Function()? sessionKey;

  @override
  State<DriverManagementNativePage> createState() => _NativePageState();
}

class _NativePageState extends State<DriverManagementNativePage>
    with WidgetsBindingObserver {
  DriverManagementNativeRepository? _repository;
  Map<String, dynamic>? _page, _detail;
  final _search = TextEditingController();
  final _plate = TextEditingController();
  final _filters = <String, String>{};
  List<String> _cursors = [''];
  int _pageIndex = 0, _generation = 0;
  String _sort = 'name', _direction = 'asc';
  int _limit = 25;
  String? _error;
  bool _busy = true, _exporting = false;
  Timer? _timer;
  int _tab = 0;
  bool _paymentManagement = false;
  String _financialAudience = '';
  final _visitedTabs = <int>{0};
  final _partnersKey = GlobalKey<DriverManagementPartnersState>();
  Object? _sessionKey;
  bool _paused = false;

  static const _statuses = {
    'online': 'Online',
    'offline': 'Offline',
    'busy': 'Bezet / op rit',
    'paused': 'Pauze',
    'inactive': 'Inactief',
    'blocked': 'Geblokkeerd',
    'unknown': 'Niet vastgesteld',
  };
  static const _sorts = {
    'name': 'Naam',
    'status': 'Status',
    'last_seen': 'Laatst gezien',
    'rides': 'Ritten',
    'created': 'Datum toegevoegd',
  };

  @override
  void initState() {
    super.initState();
    _sessionKey = widget.sessionKey?.call();
    widget.session.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  void _sessionChanged() {
    // Same authenticated company/token may be republished after an ordinary
    // bootstrap. It is not a tenant switch. Revalidate without a false logout.
    final key = widget.sessionKey?.call();
    if (widget.sessionKey != null && key != null && key == _sessionKey) {
      unawaited(_validateCurrent());
      return;
    }
    _sessionKey = key;
    _generation++;
    _timer?.cancel();
    _repository?.close();
    _repository = null;
    if (mounted) {
      setState(() {
        _page = null;
        _detail = null;
        _tab = 0;
        _paymentManagement = false;
        _financialAudience = '';
        _error = null;
        _busy = true;
      });
      unawaited(_connect());
    }
  }

  Future<void> _validateCurrent() async {
    final repo = _repository;
    if (repo == null) return;
    try {
      await repo.assertSession();
    } catch (_) {
      if (mounted && repo == _repository) await _connect();
    }
  }

  Future<void> _refreshCurrent() async {
    final repo = _repository;
    if (repo == null) {
      await _connect();
      return;
    }
    try {
      await repo.assertSession();
      if (!mounted || repo != _repository) return;
      if (_tab == 1) {
        await _partnersKey.currentState?.refresh();
      } else if (_tab == 0) {
        await _load();
      }
    } catch (e) {
      if (mounted && repo == _repository) _failure(e, _generation);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _paused = true;
    }
    if (state == AppLifecycleState.resumed && _paused && mounted) {
      _paused = false;
      // There is no 15-minute browser cookie in the native environment.
      // Expired or changed authority still clears scope before reconnecting.
      unawaited(_validateCurrent());
    }
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    _repository?.close();
    _repository = null;
    _sessionKey = widget.sessionKey?.call();
    setState(() {
      _page = null;
      _detail = null;
      _error = null;
      _busy = true;
      _cursors = [''];
      _pageIndex = 0;
    });
    try {
      final repo = await widget.connect();
      if (!mounted || generation != _generation) {
        repo.close();
        return;
      }
      await repo.connect();
      if (!mounted || generation != _generation) {
        repo.close();
        return;
      }
      _repository = repo;
      await _load(reset: true);
    } catch (error) {
      _failure(error, generation);
    }
  }

  void _failure(Object error, int generation) {
    if (!mounted || generation != _generation) return;
    setState(() {
      _page = null;
      _detail = null;
      _busy = false;
      _error = error is DriverManagementReadFailure
          ? error.message
          : 'Beheergegevens konden niet veilig worden geladen. Probeer opnieuw.';
    });
  }

  Map<String, String> get _query => {
    ..._filters,
    'q': _search.text.trim(),
    'plate': _plate.text.trim(),
    'sort': _sort,
    'direction': _direction,
    'limit': '$_limit',
    'cursor': _cursors[_pageIndex],
  };

  Future<void> _load({bool reset = false}) async {
    final repo = _repository;
    if (repo == null) return;
    if (reset) {
      _cursors = [''];
      _pageIndex = 0;
    }
    final query = _query;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await repo.list(query);
      if (mounted && generation == _generation)
        setState(() {
          _page = result;
          _busy = false;
        });
    } catch (error) {
      _failure(error, generation);
    }
  }

  void _changed() {
    _timer?.cancel();
    // Never retain an old query's data below a newly edited search/filter.
    _generation++;
    setState(() {
      _page = null;
      _detail = null;
      _busy = _repository != null;
    });
    _timer = Timer(const Duration(milliseconds: 250), () => _load(reset: true));
  }

  Future<void> _openDetail(Map<String, dynamic> driver) async {
    final repo = _repository;
    if (repo == null) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _detail = null;
    });
    try {
      final detail = await repo.detail(driver['driver_id'] as String);
      if (mounted && generation == _generation)
        setState(() {
          _detail = detail;
          _busy = false;
        });
    } catch (error) {
      _failure(error, generation);
    }
  }

  Future<void> _export() async {
    final repo = _repository;
    if (repo == null || _exporting) return;
    final generation = _generation;
    setState(() => _exporting = true);
    try {
      final csv = await repo.exportCsv(_query);
      if (!mounted || generation != _generation) return;
      await repo.assertSession();
      if (!mounted || generation != _generation) return;
      if (widget.shareCsv != null) {
        await widget.shareCsv!(csv);
      } else {
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(csv)),
              mimeType: 'text/csv',
              name: 'fluxidi-chauffeurs.csv',
            ),
          ],
          subject: 'Fluxidi chauffeurs',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
      }
    } catch (error) {
      _failure(error, generation);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _repository?.close();
    widget.session.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _plate.dispose();
    super.dispose();
  }

  String _text(dynamic value) =>
      value == null || '$value'.trim().isEmpty ? 'Niet beschikbaar' : '$value';
  String _date(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return 'Niet beschikbaar';
    final d = companyTimezoneUtcToLocal(parsed, kCompanyDefaultTimezone);
    String two(int n) => '$n'.padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  BusinessThemePalette get _palette =>
      widget.palette ??
      paletteForBusinessTheme(BusinessThemeVariant.executiveGold);
  int _detailTab = 0;

  Future<void> _action(String action, [Map<String, dynamic>? d]) async {
    final repo = _repository;
    if (repo == null) return;
    final generation = _generation;
    try {
      await repo.assertSession();
      if (!mounted || generation != _generation) return;
      if (action == 'add') {
        await widget.addDriver?.call();
      } else if (d != null) {
        if (widget.driverAction != null) {
          await widget.driverAction!(d['driver_id'] as String, action);
        } else {
          await widget.manageDriver(d['driver_id'] as String);
        }
      } else {
        if (widget.globalAction == null) {
          throw const DriverManagementReadFailure(
            'Dit beheeronderdeel is niet aangesloten.',
          );
        }
        await widget.globalAction!(action);
      }
      if (mounted && generation == _generation) {
        if (d != null && _detail != null) {
          await _openDetail(d);
        } else {
          await _load(reset: true);
        }
      }
    } catch (e) {
      if (!mounted || generation != _generation || repo != _repository) return;
      try {
        await repo.assertSession();
      } catch (_) {
        _failure(e, generation);
        return;
      }
      if (!mounted || generation != _generation || repo != _repository) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is DriverManagementReadFailure
                ? e.message
                : 'De beheeractie kon niet worden geopend. Probeer opnieuw.',
          ),
        ),
      );
    }
  }

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _palette.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _palette.border),
    ),
    child: child,
  );

  Widget _field(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: _palette.textMuted)),
        const SizedBox(height: 4),
        Text(_text(value)),
      ],
    ),
  );

  Widget _avatar(Map<String, dynamic> d, {double size = 50}) =>
      widget.avatar?.call(d['driver_id'] as String, size) ??
      CircleAvatar(
        radius: size / 2,
        backgroundColor: _palette.surfaceAlt,
        child: Icon(Icons.person_outline, color: _palette.accent),
      );

  Widget _dropdown(
    String key,
    String label,
    Map<String, String> choices,
    String value,
    void Function(String) change,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('native-filter-$key'),
    initialValue: value,
    isExpanded: true,
    dropdownColor: _palette.surface,
    decoration: InputDecoration(labelText: label),
    items: choices.entries
        .map(
          (e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, softWrap: true),
          ),
        )
        .toList(),
    onChanged: (v) {
      if (v != null) change(v);
    },
  );

  Widget _dateFilter(String key, String label) => TextButton.icon(
    icon: const Icon(Icons.calendar_today_outlined),
    label: Text(
      _filters[key] == null ? label : '$label: ${_date(_filters[key])}',
    ),
    onPressed: () async {
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (date == null || !mounted) return;
      final wall = key == 'seen_before'
          ? DateTime(date.year, date.month, date.day, 23, 59, 59)
          : date;
      _filters[key] = companyTimezoneLocalToUtc(
        wall,
        kCompanyDefaultTimezone,
      ).toIso8601String();
      _changed();
    },
  );

  Widget _filtersPanel() => ExpansionTile(
    key: const ValueKey('native-driver-filters'),
    tilePadding: EdgeInsets.zero,
    minTileHeight: 40,
    title: const Text('Meer filters'),
    leading: const Icon(Icons.tune),
    children: [
      LayoutBuilder(
        builder: (context, c) {
          final columns = c.maxWidth >= 500 ? 2 : 1;
          final width = (c.maxWidth - 12 * (columns - 1)) / columns;
          Widget filter(
            String key,
            String label,
            Map<String, String> choices,
          ) => SizedBox(
            width: width,
            child: _dropdown(key, label, choices, _filters[key] ?? '', (v) {
              _filters[key] = v;
              _changed();
            }),
          );
          return Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              filter('status', 'Status', {'': 'Alle statussen', ..._statuses}),
              filter('active', 'Account', {
                '': 'Alle accounts',
                'true': 'Actief',
                'false': 'Inactief',
              }),
              filter('vehicle', 'Voertuigkoppeling', {
                '': 'Met en zonder voertuig',
                'with': 'Met voertuig',
                'without': 'Zonder voertuig',
              }),
              filter('vehicle_type', 'Voertuigtype', {
                '': 'Alle types',
                for (final t in _repository?.vehicleTypes ?? <String>[]) t: t,
              }),
              SizedBox(
                width: width,
                child: TextField(
                  key: const ValueKey('native-driver-plate'),
                  controller: _plate,
                  onChanged: (_) => _changed(),
                  decoration: const InputDecoration(
                    labelText: 'Kenteken bevat',
                  ),
                ),
              ),
            ],
          );
        },
      ),
      Wrap(
        spacing: 8,
        children: [
          _dateFilter('seen_after', 'Laatst gezien vanaf'),
          _dateFilter('seen_before', 'Laatst gezien tot en met'),
        ],
      ),
      TextButton.icon(
        onPressed: () {
          _search.clear();
          _plate.clear();
          _filters.clear();
          _load(reset: true);
        },
        icon: const Icon(Icons.filter_alt_off),
        label: const Text('Filters wissen'),
      ),
    ],
  );

  String _vehicles(Map<String, dynamic> d) {
    final v = d['vehicles'] as List;
    return v.isEmpty
        ? 'Zonder voertuig'
        : v
              .map(
                (v) => [
                  v['vehicle_name'],
                  v['license_plate'],
                ].where((x) => x != null && '$x'.trim().isNotEmpty).join(' · '),
              )
              .join('\n');
  }

  Widget _tile(
    String label,
    IconData icon,
    VoidCallback? tap, {
    bool selected = false,
  }) => Material(
    color: selected ? _palette.accent : _palette.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: _palette.border),
    ),
    child: InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: selected ? _palette.textOnAccent : _palette.accent,
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? _palette.textOnAccent
                      : _palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _categories() => Row(
    children: [
      for (final e in [
        ('Voertuigen', Icons.directions_car_outlined, 'vehicles'),
        ('Documenten', Icons.description_outlined, 'documents'),
        ('Codes & QR', Icons.qr_code_2, 'codes'),
      ])
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: e.$3 == 'codes' ? 0 : 8),
            child: KeyedSubtree(
              key: ValueKey('management-action-${e.$3}'),
              child: _tile(e.$1, e.$2, () => _action(e.$3)),
            ),
          ),
        ),
    ],
  );

  Color _statusColor(String? status) => switch (status) {
    'online' => _palette.success,
    'paused' =>
      _palette.isDark ? Colors.orange.shade300 : Colors.orange.shade900,
    'offline' => _palette.isDark ? Colors.grey.shade400 : Colors.grey.shade700,
    'blocked' || 'inactive' => _palette.danger,
    _ => _palette.textMuted,
  };

  Widget _statusLabel(Map<String, dynamic> d) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 10, color: _statusColor(d['status'] as String?)),
      const SizedBox(width: 6),
      Text(
        _statuses[d['status']] ?? 'Niet vastgesteld',
        style: const TextStyle(fontSize: 12),
      ),
    ],
  );

  Widget _driverCard(Map<String, dynamic> d) => Material(
    color: _palette.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: _palette.border),
    ),
    child: InkWell(
      key: ValueKey('native-driver-detail-${d['driver_id']}'),
      onTap: () {
        _detailTab = 0;
        _openDetail(d);
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(d),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _text(d['display_name']),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _vehicles(d),
                    style: TextStyle(color: _palette.textMuted),
                  ),
                  if ((d['contact'] as Map?)?['phone'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '${d['contact']['phone']}',
                        style: TextStyle(
                          color: _palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _statusLabel(d),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _palette.accent),
          ],
        ),
      ),
    ),
  );

  Widget _sortPanel() => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      PopupMenuButton<String>(
        key: const ValueKey('native-filter-sort'),
        tooltip: 'Sorteren',
        onSelected: (v) {
          if (v.startsWith('direction:')) {
            _direction = v.substring(10);
          } else {
            _sort = v;
          }
          _load(reset: true);
        },
        itemBuilder: (_) => [
          for (final e in _sorts.entries)
            CheckedPopupMenuItem(
              value: e.key,
              checked: _sort == e.key,
              child: Text(e.value),
            ),
          const PopupMenuDivider(),
          CheckedPopupMenuItem(
            value: 'direction:asc',
            checked: _direction == 'asc',
            child: const Text('Oplopend'),
          ),
          CheckedPopupMenuItem(
            value: 'direction:desc',
            checked: _direction == 'desc',
            child: const Text('Aflopend'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort, color: _palette.accent),
              const SizedBox(width: 6),
              Text('Sorteren', style: TextStyle(color: _palette.accent)),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _list() => _error != null
      ? ListView(padding: const EdgeInsets.all(16), children: [_errorPanel()])
      : ListView(
          key: const ValueKey('management-list'),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Chauffeurbeheer',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Beheer je chauffeurs en houd overzicht.',
              style: TextStyle(color: _palette.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('native-driver-search'),
              controller: _search,
              onChanged: (_) => _changed(),
              decoration: const InputDecoration(
                hintText: 'Naam, telefoon, e-mail of kenteken',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in {
                  '': 'Alle',
                  'online': 'Online',
                  'offline': 'Offline',
                  'paused': 'Pauze',
                }.entries)
                  ChoiceChip(
                    showCheckmark: false,
                    selectedColor: _palette.accent,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: (_filters['status'] ?? '') == e.key
                          ? _palette.textOnAccent
                          : _palette.textPrimary,
                    ),
                    avatar: Icon(
                      e.key.isEmpty ? Icons.people_outline : Icons.circle,
                      size: e.key.isEmpty ? 18 : 10,
                      color: e.key.isEmpty
                          ? ((_filters['status'] ?? '').isEmpty
                                ? _palette.textOnAccent
                                : _palette.accent)
                          : _statusColor(e.key),
                    ),
                    label: Text(e.value),
                    selected: (_filters['status'] ?? '') == e.key,
                    onSelected: (_) {
                      _filters['status'] = e.key;
                      _changed();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _categories(),
            const SizedBox(height: 8),
            _filtersPanel(),
            const SizedBox(height: 4),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_page != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_page!['total']} chauffeurs',
                      key: const ValueKey('native-driver-count'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _sortPanel(),
                ],
              ),
              const SizedBox(height: 12),
              if ((_page!['items'] as List).isEmpty)
                _panel(
                  const Text('Geen chauffeurs gevonden voor deze filters.'),
                ),
              for (final d in _page!['items'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _driverCard(d),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    child: _dropdown(
                      'limit',
                      'Per pagina',
                      {'25': '25', '50': '50', '100': '100'},
                      '$_limit',
                      (v) {
                        _limit = int.parse(v);
                        _load(reset: true);
                      },
                    ),
                  ),
                  Text(
                    _page!['total'] == 0
                        ? '0 resultaten'
                        : '${_page!['offset'] + 1}–${_page!['offset'] + (_page!['items'] as List).length} van ${_page!['total']}',
                  ),
                  TextButton(
                    key: const ValueKey('native-driver-previous'),
                    onPressed: _busy || _pageIndex == 0
                        ? null
                        : () {
                            _pageIndex--;
                            _load();
                          },
                    child: const Text('Vorige'),
                  ),
                  TextButton(
                    key: const ValueKey('native-driver-next'),
                    onPressed: _busy || _page!['next_cursor'] == null
                        ? null
                        : () {
                            _cursors = [
                              ..._cursors.take(_pageIndex + 1),
                              _page!['next_cursor'] as String,
                            ];
                            _pageIndex++;
                            _load();
                          },
                    child: const Text('Volgende'),
                  ),
                ],
              ),
            ],
          ],
        );

  Widget _errorPanel() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_error!, key: const ValueKey('native-driver-error')),
        TextButton(onPressed: _connect, child: const Text('Opnieuw proberen')),
        if (widget.recoverSession != null)
          TextButton(
            onPressed: widget.recoverSession,
            child: const Text('Bedrijfslogin'),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Meer herstelopties'),
          children: [
            TextButton.icon(
              key: const ValueKey('native-driver-legacy'),
              onPressed: widget.openLegacy,
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Eerdere beheerpagina'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _details(Map<String, dynamic> d) => ListView(
    key: ValueKey('management-details-${d['driver_id']}'),
    padding: const EdgeInsets.all(16),
    children: [
      TextButton.icon(
        onPressed: () => setState(() => _detail = null),
        icon: const Icon(Icons.arrow_back),
        label: const Text('Chauffeurs'),
      ),
      Row(
        children: [
          _avatar(d, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _text(d['display_name']),
              key: const ValueKey('native-driver-detail-title'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, c) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in [
              ('Bewerken', Icons.edit_outlined, 'edit'),
              ('Rooster', Icons.calendar_month_outlined, 'schedule'),
              ('Codes & QR', Icons.qr_code_2, 'codes'),
              ('Meer', Icons.more_horiz, 'manage'),
            ])
              SizedBox(
                width: (c.maxWidth - 8) / 2,
                child: _tile(e.$1, e.$2, () => _action(e.$3, d)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    [
                      'Overzicht',
                      'Voertuig',
                      'Documenten',
                      'Codes & QR',
                      'Ritten',
                    ][i],
                  ),
                  selected: _detailTab == i,
                  onSelected: (_) => setState(() => _detailTab = i),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (_detailTab == 0) ...[
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Status en contact',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              _field('Status', _statuses[d['status']] ?? 'Niet vastgesteld'),
              _field('Laatst gezien', _date(d['last_seen_at'])),
              _field('Telefoon', (d['contact'] as Map?)?['phone']),
              _field('E-mail', (d['contact'] as Map?)?['email']),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voertuig',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              _field('Gekoppeld voertuig', _vehicles(d)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _action('vehicle', d),
                icon: const Icon(Icons.directions_car_outlined),
                label: const Text('Voertuig kiezen of wijzigen'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Account en toegang',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              _field(
                'Account',
                d['is_active'] == null
                    ? 'Niet vastgesteld'
                    : d['is_active'] == true
                    ? 'Actief'
                    : 'Inactief',
              ),
              TextButton.icon(
                onPressed: () => _action('pin', d),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Persoonlijke PIN'),
              ),
            ],
          ),
        ),
      ],
      if (_detailTab == 1)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field('Gekoppelde voertuigen', _vehicles(d)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _action('vehicle', d),
                child: const Text('Voertuigtoewijzing beheren'),
              ),
            ],
          ),
        ),
      if (_detailTab == 2)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Documenten',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _action('documents', d),
                child: const Text('Documenten beheren'),
              ),
            ],
          ),
        ),
      if (_detailTab == 3) ...[
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vaste inlogcode / chauffeurcode',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Voor aanmelden en herstel. Een bestaande volledige code wordt niet opnieuw getoond.',
              ),
              TextButton(
                onPressed: () => _action('loginCode', d),
                child: const Text('Nieuwe inlogcode genereren'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tijdelijke koppelcode & QR',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Eenmalig koppelen met een vervaltijd. Afzonderlijk van de persoonlijke PIN.',
              ),
              TextButton.icon(
                onPressed: () => _action('qr', d),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Tijdelijke koppel-QR maken'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _action('pin', d),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Persoonlijke PIN'),
        ),
      ],
      if (_detailTab == 4)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field('Aantal ritten', d['ride_count']),
              _field(
                'Huidige rit',
                (d['current_trip'] as Map?)?['booking_reference'],
              ),
              TextButton.icon(
                onPressed: () => _action('reports', d),
                icon: const Icon(Icons.insights_outlined),
                label: const Text('Ritten en rapporten'),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      TextButton.icon(
        key: const ValueKey('native-driver-existing-actions'),
        onPressed: () => _action('manage', d),
        icon: const Icon(Icons.manage_accounts_outlined),
        label: const Text('Alle beheeracties voor deze chauffeur'),
      ),
    ],
  );

  Widget _companyHeader() {
    final b = widget.companyBranding;
    Widget fallback() => Image.asset(
      _palette.isDark
          ? 'assets/fluxidi/fluxidi_logo_horizontal_gold.png'
          : 'assets/fluxidi/fluxidi_logo_horizontal_dark.png',
      height: 28,
      width: 145,
      fit: BoxFit.contain,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (b != null && b.hasLogo)
          SizedBox(
            height: 28,
            width: 145,
            child: Image(
              image: headerImageProvider(b.displayLogoUrl),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => fallback(),
            ),
          )
        else
          fallback(),
        if (b != null && b.companyName.isNotEmpty)
          Text(
            b.companyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: _palette.textSecondary),
          ),
      ],
    );
  }

  Widget _financialMetrics() => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 900
          ? 4
          : c.maxWidth >= 250 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.8
          ? 2
          : 1;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final m in const [
            ('Open te betalen', Icons.account_balance_wallet_outlined),
            ('Klaar voor uitbetaling', Icons.check_circle_outline),
            ('Uitbetaald deze maand', Icons.payments_outlined),
            ('In controle', Icons.pending_outlined),
          ])
            SizedBox(
              key: ValueKey('management-financial-metric-${m.$1}'),
              width: (c.maxWidth - 10 * (columns - 1)) / columns,
              child: _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(m.$2, size: 26),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '—',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      m.$1,
                      style: TextStyle(
                        fontSize: c.maxWidth / columns < 180 ? 11 : 12,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    driverManagementReadableText(
                      'Nog niet beschikbaar',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        color: _palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _financialAudienceFilters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final e in const {
          '': 'Alles',
          'partner': 'Partners',
          'subcontractor': 'Onderaannemers',
          'driver': 'Chauffeurs',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: ValueKey('management-financial-audience-${e.key}'),
              label: Text(e.value),
              selected: _financialAudience == e.key,
              onSelected: (_) => setState(() => _financialAudience = e.key),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    ),
  );

  Widget _financialObligations() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Afrekeningen nog niet beschikbaar',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          'Hier verschijnen gecontroleerde bedragen, begunstigden en betaalstatussen zodra de financiële bron is aangesloten.',
          style: TextStyle(fontSize: 13, color: _palette.textMuted),
        ),
      ],
    ),
  );

  Widget _paymentManagementView() => ListView(
    key: const ValueKey('management-payment-selection'),
    padding: const EdgeInsets.all(16),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('management-payments-back'),
          onPressed: () => setState(() => _paymentManagement = false),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Afrekeningen'),
        ),
      ),
      const Text(
        'Betalingen beheren',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        'Controleer bedragen, begunstigden en betaalbewijs.',
        style: TextStyle(color: _palette.textMuted),
      ),
      const SizedBox(height: 16),
      _panel(
        const Text(
          'Er zijn nog geen betrouwbaar gekoppelde afrekeningen of begunstigden. Selecteren en uitbetalen zijn geblokkeerd totdat betaalrechten, backend en betaalprovider zijn gecontroleerd.',
        ),
      ),
      const SizedBox(height: 16),
      _financialAudienceFilters(),
      const SizedBox(height: 16),
      for (final e in const [
        ('Klaar voor uitbetaling', Icons.check_circle_outline),
        ('Controle nodig', Icons.pending_outlined),
        ('Geblokkeerd', Icons.lock_outline),
        ('Betaalhistoriek & bewijs', Icons.receipt_long_outlined),
      ]) ...[
        _panel(
          Row(
            children: [
              Icon(e.$2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.$1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text('Nog niet beschikbaar'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      const CheckboxListTile(
        key: ValueKey('management-payment-select-all-blocked'),
        value: false,
        onChanged: null,
        title: Text('Meerdere afrekeningen selecteren'),
        subtitle: Text('Nog niet beschikbaar'),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      _field('Geselecteerd bedrag', 'Nog niet beschikbaar'),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('management-payout-blocked'),
        onPressed: null,
        icon: const Icon(Icons.lock_outline),
        label: const Text('Uitbetalen niet beschikbaar'),
      ),
    ],
  );

  Widget _paymentsOverview() => _paymentManagement
      ? _paymentManagementView()
      : ListView(
          key: const ValueKey('management-payments'),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Afrekeningen',
              key: ValueKey('management-payments-title'),
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Je bedrijfsafrekeningen en betaalhistorie',
              style: TextStyle(color: _palette.textMuted),
            ),
            const SizedBox(height: 16),
            _financialMetrics(),
            const SizedBox(height: 16),
            _financialAudienceFilters(),
            const SizedBox(height: 12),
            const TextField(
              key: ValueKey('management-financial-search-unavailable'),
              enabled: false,
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Zoeken in afrekeningen',
                helperText: 'Beschikbaar zodra afrekeningen zijn aangesloten',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Te betalen',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.sort),
                  label: const Text('Sorteren'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _financialObligations(),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('management-payments-manage'),
              onPressed: _repository == null || _error != null
                  ? null
                  : () => setState(() => _paymentManagement = true),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Betalingen beheren'),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: _palette.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Financiële bron nog niet aangesloten. Er worden geen betalingen uitgevoerd.',
                    style: TextStyle(fontSize: 12, color: _palette.textMuted),
                  ),
                ),
              ],
            ),
          ],
        );

  @override
  Widget build(BuildContext context) => Theme(
    data: driverManagementTheme(_palette),
    child: Builder(
      builder: (context) => PopScope(
        canPop: _detail == null && _tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            if (_tab == 2 && _paymentManagement) {
              setState(() => _paymentManagement = false);
              return;
            }
            if (_tab == 1 && (_partnersKey.currentState?.goBack() ?? false))
              return;
            setState(() {
              _detail = null;
              _tab = 0;
            });
          }
        },
        child: Scaffold(
          key: const ValueKey('native-driver-management-page'),
          bottomNavigationBar:
              _tab == 0 &&
                  _detail == null &&
                  _repository != null &&
                  _error == null
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy || _exporting ? null : _export,
                          icon: const Icon(Icons.download_outlined),
                          label: Text(
                            _exporting ? 'Exporteren…' : 'Export CSV',
                          ),
                        ),
                        if (widget.addDriver != null)
                          FloatingActionButton(
                            key: const ValueKey('native-driver-add'),
                            tooltip: 'Chauffeur toevoegen',
                            onPressed: _busy ? null : () => _action('add'),
                            backgroundColor: _palette.accent,
                            foregroundColor: _palette.textOnAccent,
                            elevation: 0,
                            shape: const CircleBorder(),
                            child: const Icon(Icons.add, size: 32),
                          ),
                      ],
                    ),
                  ),
                )
              : null,
          appBar: AppBar(
            centerTitle: true,
            title: _companyHeader(),
            actions: [
              IconButton(
                tooltip: 'Vernieuwen',
                onPressed: _busy ? null : _refreshCurrent,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                SingleChildScrollView(
                  key: const ValueKey('management-main-tabs'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: ChoiceChip(
                            key: ValueKey('management-tab-$i'),
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            padding: const EdgeInsets.all(8),
                            showCheckmark: false,
                            avatar: Icon(
                              [
                                Icons.people_outline,
                                Icons.apartment,
                                Icons.receipt_long_outlined,
                              ][i],
                              size: 18,
                              color: _tab == i
                                  ? _palette.textOnAccent
                                  : _palette.accent,
                            ),
                            label: Text(
                              ['Chauffeurs', 'Partners', 'Afrekeningen'][i],
                            ),
                            labelStyle: TextStyle(
                              fontSize: MediaQuery.sizeOf(context).width < 450
                                  ? 12
                                  : 14,
                              color: _tab == i
                                  ? _palette.textOnAccent
                                  : _palette.textPrimary,
                            ),
                            selectedColor: _palette.accent,
                            selected: _tab == i,
                            onSelected: _repository == null || _error != null
                                ? null
                                : (_) => setState(() {
                                    _tab = i;
                                    _visitedTabs.add(i);
                                    if (i == 0) _detail = null;
                                  }),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      LayoutBuilder(
                        builder: (context, c) {
                          if (c.maxWidth >= 900 && _detail != null)
                            return Row(
                              children: [
                                Expanded(flex: 5, child: _list()),
                                const VerticalDivider(width: 1),
                                Expanded(flex: 6, child: _details(_detail!)),
                              ],
                            );
                          return _detail == null ? _list() : _details(_detail!);
                        },
                      ),
                      if (_visitedTabs.contains(1) &&
                          _repository != null &&
                          _error == null)
                        DriverManagementPartners(
                          key: _partnersKey,
                          repository: _repository!,
                        )
                      else
                        ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_error != null)
                              _errorPanel()
                            else if (_tab == 1)
                              const LinearProgressIndicator(),
                          ],
                        ),
                      _paymentsOverview(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
