// COMPANY-CUSTOMER-OPS-P0 — shared agenda color chips for admin and Chauffeurs.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';

export 'package:fluxidi_tracking/company/company_driver_agenda_color.dart';

const Key kCompanyDriverAgendaColorsPanelKey = Key(
  'company_driver_agenda_colors_panel',
);
const Key kCompanyDriverAgendaColorPickerKey = Key(
  'company_driver_agenda_color_picker',
);
const Key kCompanyDriverAgendaColorSaveKey = Key(
  'company_driver_agenda_color_save',
);
const Key kCompanyDriverAgendaColorSavedBannerKey = Key(
  'company_driver_agenda_color_saved',
);
const Key kCompanyDriverAgendaColorPreviewKey = Key(
  'company_driver_agenda_color_preview',
);
const Key kCompanyDriverAgendaCustomColorKey = Key(
  'company_driver_agenda_color_custom',
);
const Key kCompanyDriverAgendaCustomHexFieldKey = Key(
  'company_driver_agenda_color_custom_hex',
);

final ValueNotifier<int> companyDriverAgendaColorsTick = ValueNotifier<int>(0);

final Map<String, String> _companyDriverAgendaColorCache = <String, String>{};

void notifyCompanyDriverAgendaColorsChanged() {
  companyDriverAgendaColorsTick.value += 1;
}

void rememberCompanyDriverAgendaColor(String driverId, String color) {
  final id = driverId.trim();
  if (id.isEmpty) return;
  _companyDriverAgendaColorCache[id] = color.trim();
}

String cachedCompanyDriverAgendaColor(String driverId) {
  return _companyDriverAgendaColorCache[driverId.trim()] ?? '';
}

void resetCompanyDriverAgendaColorCacheForTest() {
  _companyDriverAgendaColorCache.clear();
}

Future<void> saveCompanyDriverAgendaColor({
  required Map<String, dynamic> driver,
  required String color,
  Future<void> Function(Map<String, dynamic> driver)? driverUpsert,
}) async {
  final driverId = companyAgendaDriverId(driver);
  if (driverId.isEmpty) return;
  final hex = normalizeCompanyAgendaColorHex(color);
  if (hex.isEmpty) return;
  await (driverUpsert ?? upsertCompanyOpsDriver)(<String, dynamic>{
    ...driver,
    'driver_id': driverId,
    'agenda_color': hex,
  });
  rememberCompanyDriverAgendaColor(driverId, hex);
  notifyCompanyDriverAgendaColorsChanged();
}

Key companyDriverAgendaColorChipKey(String color) =>
    Key('company_driver_agenda_color_${color.trim().toUpperCase()}');

Key companyDriverAgendaColorCheckKey(String color) =>
    Key('company_driver_agenda_color_check_${color.trim().toUpperCase()}');

Key companyDriverAgendaColorActionKey(String driverId) =>
    Key('company_driver_agenda_color_action_${driverId.trim()}');

Key companyDriverAgendaColorSwatchKey(String driverId) =>
    Key('company_driver_agenda_color_swatch_${driverId.trim()}');

bool companyDriverAgendaColorIsSelected(String selected, String color) {
  return normalizeCompanyAgendaColorHex(selected) ==
      normalizeCompanyAgendaColorHex(color);
}

class CompanyDriverAgendaColorChips extends StatelessWidget {
  const CompanyDriverAgendaColorChips({
    super.key,
    required this.selected,
    required this.onSelect,
    this.enabled = true,
    this.usedBy = const <String, List<String>>{},
  });

  final String selected;
  final ValueChanged<String> onSelect;
  final bool enabled;
  final Map<String, List<String>> usedBy;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= 520 ? 5 : 4;
    final rows = <Widget>[];
    for (var i = 0; i < kCompanyDriverAgendaColorChoices.length; i += columns) {
      final slice = kCompanyDriverAgendaColorChoices.skip(i).take(columns);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              for (final color in slice)
                Expanded(
                  child: _CompanyDriverAgendaColorChip(
                    color: color,
                    selected: companyDriverAgendaColorIsSelected(
                      selected,
                      color,
                    ),
                    enabled: enabled,
                    occupancy: companyAgendaColorOccupancyShort(
                      companyAgendaColorUsers(usedBy, color),
                    ),
                    onSelect: onSelect,
                  ),
                ),
              for (var s = slice.length; s < columns; s += 1)
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _CompanyDriverAgendaColorChip extends StatelessWidget {
  const _CompanyDriverAgendaColorChip({
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    this.occupancy = '',
  });

  final String color;
  final bool selected;
  final bool enabled;
  final String occupancy;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final fill = companyAgendaColorFromHex(color, fallbackSeed: color);
    final checkColor = companyAgendaOnColor(fill);
    return Tooltip(
      message: occupancy.isEmpty ? color : occupancy,
      child: InkWell(
        key: companyDriverAgendaColorChipKey(color),
        onTap: enabled ? () => onSelect(color) : null,
        borderRadius: BorderRadius.circular(8),
        child: Semantics(
          selected: selected,
          button: true,
          label: occupancy.isEmpty ? color : '$color $occupancy',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).dividerColor,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: selected
                    ? Icon(
                        Icons.check,
                        key: companyDriverAgendaColorCheckKey(color),
                        size: 16,
                        color: checkColor,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 2),
              Text(
                occupancy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontSize: 9.5, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompanyDriverAgendaColorPreview extends StatelessWidget {
  const CompanyDriverAgendaColorPreview({
    super.key,
    required this.driver,
    required this.color,
    required this.language,
  });

  final Map<String, dynamic> driver;
  final String color;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final look = companyAgendaDriverLook(<String, dynamic>{
      ...driver,
      'agenda_color': normalizeCompanyAgendaColorHex(color),
    });
    final onColor = companyAgendaOnColor(look.color);
    final photo = look.photoUrl;
    return Container(
      key: kCompanyDriverAgendaColorPreviewKey,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: look.color,
            backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
            onBackgroundImageError: photo.isEmpty ? null : (_, _) {},
            child: photo.isEmpty
                ? Text(
                    look.initials,
                    style: TextStyle(
                      color: onColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kCompanyAgendaColorPreview.of(language),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  look.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CompanyDriverAgendaColorPickerDialog extends StatefulWidget {
  const CompanyDriverAgendaColorPickerDialog({
    super.key,
    required this.driver,
    required this.selected,
    required this.language,
    this.companyDrivers = const <Map<String, dynamic>>[],
    this.driverUpsert,
  });

  final Map<String, dynamic> driver;
  final String selected;
  final AppLanguage language;
  final List<Map<String, dynamic>> companyDrivers;
  final Future<void> Function(Map<String, dynamic> driver)? driverUpsert;

  @override
  State<CompanyDriverAgendaColorPickerDialog> createState() =>
      _CompanyDriverAgendaColorPickerDialogState();
}

class _CompanyDriverAgendaColorPickerDialogState
    extends State<CompanyDriverAgendaColorPickerDialog> {
  late String _draft;
  late TextEditingController _hexCtrl;
  bool _customOpen = false;

  AppLanguage get _lang => widget.language;

  Map<String, List<String>> get _usedBy => companyAgendaColorUsageByHex(
    widget.companyDrivers,
    excludeDriverId: companyAgendaDriverId(widget.driver),
  );

  @override
  void initState() {
    super.initState();
    _draft = normalizeCompanyAgendaColorHex(widget.selected);
    if (_draft.isEmpty) {
      _draft = normalizeCompanyAgendaColorHex(
        cachedCompanyDriverAgendaColor(companyAgendaDriverId(widget.driver)),
      );
    }
    if (_draft.isEmpty) {
      _draft = kCompanyDriverAgendaColorChoices.first;
    }
    _customOpen = companyAgendaColorIsCustom(_draft);
    _hexCtrl = TextEditingController(text: _draft.replaceFirst('#', ''));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _selectStandard(String color) {
    final hex = normalizeCompanyAgendaColorHex(color);
    if (hex.isEmpty) return;
    setState(() {
      _draft = hex;
      _customOpen = false;
      _hexCtrl.text = hex.replaceFirst('#', '');
    });
  }

  void _openCustom() {
    setState(() {
      _customOpen = true;
      if (!companyAgendaColorIsCustom(_draft) &&
          normalizeCompanyAgendaColorHex(_draft).isNotEmpty) {
        // Keep the current standard color as the custom starting point.
      }
      _hexCtrl.text = _draft.replaceFirst('#', '');
    });
  }

  void _setCustomHex(String raw) {
    final hex = normalizeCompanyAgendaColorHex(
      raw.startsWith('#') ? raw : '#$raw',
    );
    if (hex.isEmpty) return;
    setState(() {
      _draft = hex;
      _customOpen = true;
      if (_hexCtrl.text.toUpperCase() != hex.replaceFirst('#', '')) {
        _hexCtrl.value = TextEditingValue(
          text: hex.replaceFirst('#', ''),
          selection: TextSelection.collapsed(offset: hex.length - 1),
        );
      }
    });
  }

  Future<void> _save() async {
    try {
      await saveCompanyDriverAgendaColor(
        driver: widget.driver,
        color: _draft,
        driverUpsert: widget.driverUpsert,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(kCompanyAgendaColorSaveFailed.of(_lang))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final used = companyAgendaColorUsers(_usedBy, _draft);
    final hsv = HSVColor.fromColor(
      companyAgendaColorFromHex(_draft, fallbackSeed: _draft),
    );
    return AlertDialog(
      key: kCompanyDriverAgendaColorPickerKey,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(kCompanyAgendaColorChange.of(_lang)),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width >= 520
            ? 420
            : MediaQuery.sizeOf(context).width - 48,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              CompanyDriverAgendaColorPreview(
                driver: widget.driver,
                color: _draft,
                language: _lang,
              ),
              const SizedBox(height: 8),
              Text(
                kCompanyAgendaColorIdentityHint.of(_lang),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (used.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  companyAgendaColorUsedByText(used, _lang),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              CompanyDriverAgendaColorChips(
                selected: _customOpen ? '' : _draft,
                usedBy: _usedBy,
                onSelect: _selectStandard,
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: kCompanyDriverAgendaCustomColorKey,
                  onPressed: _openCustom,
                  icon: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: companyAgendaColorFromHex(
                        _draft,
                        fallbackSeed: _draft,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _customOpen
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).dividerColor,
                        width: _customOpen ? 2 : 1,
                      ),
                    ),
                    child: _customOpen
                        ? Icon(
                            Icons.check,
                            key: companyDriverAgendaColorCheckKey(_draft),
                            size: 12,
                            color: companyAgendaOnColor(
                              companyAgendaColorFromHex(
                                _draft,
                                fallbackSeed: _draft,
                              ),
                            ),
                          )
                        : null,
                  ),
                  label: Text(kCompanyAgendaColorCustom.of(_lang)),
                ),
              ),
              if (_customOpen) ...[
                const SizedBox(height: 8),
                Slider(
                  value: hsv.hue,
                  max: 359,
                  onChanged: (hue) {
                    _setCustomHex(
                      companyAgendaColorHexFromColor(
                        HSVColor.fromAHSV(
                          1,
                          hue,
                          hsv.saturation.clamp(0.35, 1),
                          hsv.value.clamp(0.35, 0.85),
                        ).toColor(),
                      ),
                    );
                  },
                ),
                TextField(
                  key: kCompanyDriverAgendaCustomHexFieldKey,
                  controller: _hexCtrl,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    labelText: kCompanyAgendaColorCustomHex.of(_lang),
                    prefixText: '#',
                  ),
                  onChanged: _setCustomHex,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(kCompanyAgendaCancel.of(_lang)),
        ),
        FilledButton(
          key: kCompanyDriverAgendaColorSaveKey,
          onPressed: normalizeCompanyAgendaColorHex(_draft).isEmpty
              ? null
              : _save,
          child: Text(kCompanyAgendaColorSave.of(_lang)),
        ),
      ],
    );
  }
}

Future<bool> showCompanyDriverAgendaColorPicker({
  required BuildContext context,
  required Map<String, dynamic> driver,
  required String selected,
  AppLanguage? language,
  List<Map<String, dynamic>> companyDrivers = const <Map<String, dynamic>>[],
  Future<void> Function(Map<String, dynamic> driver)? driverUpsert,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return CompanyDriverAgendaColorPickerDialog(
        driver: driver,
        selected: selected,
        language: language ?? appLanguageNotifier.value,
        companyDrivers: companyDrivers,
        driverUpsert: driverUpsert,
      );
    },
  );
  return saved == true;
}

class CompanyDriverAgendaColorAction extends StatefulWidget {
  const CompanyDriverAgendaColorAction({
    super.key,
    required this.driver,
    this.language,
    this.driversLoader,
    this.driverUpsert,
    this.compact = false,
  });

  final Map<String, dynamic> driver;
  final AppLanguage? language;
  final Future<List<Map<String, dynamic>>> Function()? driversLoader;
  final Future<void> Function(Map<String, dynamic> driver)? driverUpsert;
  final bool compact;

  @override
  State<CompanyDriverAgendaColorAction> createState() =>
      _CompanyDriverAgendaColorActionState();
}

class _CompanyDriverAgendaColorActionState
    extends State<CompanyDriverAgendaColorAction> {
  late String _color;
  List<Map<String, dynamic>> _companyDrivers = const <Map<String, dynamic>>[];

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  String get _driverId => companyAgendaDriverId(widget.driver);

  @override
  void initState() {
    super.initState();
    _color = _colorFrom(widget.driver);
    if (_color.isEmpty) {
      _color = cachedCompanyDriverAgendaColor(_driverId);
    }
    companyDriverAgendaColorsTick.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyDriverAgendaColorAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (companyAgendaDriverId(oldWidget.driver) != _driverId) {
      _color = _colorFrom(widget.driver);
      _load();
    }
  }

  @override
  void dispose() {
    companyDriverAgendaColorsTick.removeListener(_load);
    super.dispose();
  }

  String _colorFrom(Map<String, dynamic> driver) {
    return (driver['agenda_color'] ?? driver['agendaColor'] ?? '').toString();
  }

  Future<void> _load() async {
    final cached = cachedCompanyDriverAgendaColor(_driverId);
    if (cached.isNotEmpty && cached != _color && mounted) {
      setState(() => _color = cached);
    }
    try {
      final drivers = await (widget.driversLoader ?? fetchCompanyOpsDrivers)();
      if (!mounted) return;
      _companyDrivers = drivers;
      for (final item in drivers) {
        if (companyAgendaDriverId(item) == _driverId) {
          final next = _colorFrom(item);
          rememberCompanyDriverAgendaColor(_driverId, next);
          if (next != _color) {
            setState(() => _color = next);
          }
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _changeColor() async {
    final saved = await showCompanyDriverAgendaColorPicker(
      context: context,
      driver: widget.driver,
      selected: _color,
      language: _lang,
      companyDrivers: _companyDrivers,
      driverUpsert: widget.driverUpsert,
    );
    if (!mounted || !saved) return;
    setState(() => _color = cachedCompanyDriverAgendaColor(_driverId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: kCompanyDriverAgendaColorSavedBannerKey,
        content: Text(kCompanyAgendaColorSaved.of(_lang)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swatch = companyAgendaColorFromHex(
      _color,
      fallbackSeed: _driverId.isEmpty ? kCompanyAgendaColorLabel.nl : _driverId,
    );
    final labelStyle = TextStyle(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w700,
      fontSize: widget.compact ? 12.2 : 13.4,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        key: companyDriverAgendaColorActionKey(_driverId),
        onTap: _changeColor,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 2 : 4,
            vertical: widget.compact ? 2 : 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: companyDriverAgendaColorSwatchKey(_driverId),
                width: widget.compact ? 14 : 16,
                height: widget.compact ? 14 : 16,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.dividerColor.withOpacity(0.7),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  kCompanyAgendaColorChange.of(_lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompanyDriverAgendaColorsPanel extends StatefulWidget {
  const CompanyDriverAgendaColorsPanel({
    super.key,
    this.language,
    this.driversLoader,
    this.driverUpsert,
    this.listedDrivers,
  });

  final AppLanguage? language;
  final Future<List<Map<String, dynamic>>> Function()? driversLoader;
  final Future<void> Function(Map<String, dynamic> driver)? driverUpsert;
  final List<Map<String, dynamic>>? listedDrivers;

  @override
  State<CompanyDriverAgendaColorsPanel> createState() =>
      _CompanyDriverAgendaColorsPanelState();
}

class _CompanyDriverAgendaColorsPanelState
    extends State<CompanyDriverAgendaColorsPanel> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _drivers = const <Map<String, dynamic>>[];

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  List<Map<String, dynamic>> get _visibleDrivers {
    final listed = widget.listedDrivers;
    if (listed != null && listed.isNotEmpty) return listed;
    return _drivers;
  }

  String _colorFor(Map<String, dynamic> driver) {
    final id = companyAgendaDriverId(driver);
    final cached = cachedCompanyDriverAgendaColor(id);
    if (cached.isNotEmpty) return cached;
    for (final item in _drivers) {
      if (companyAgendaDriverId(item) == id) {
        return (item['agenda_color'] ?? item['agendaColor'] ?? '').toString();
      }
    }
    return (driver['agenda_color'] ?? driver['agendaColor'] ?? '').toString();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drivers = await (widget.driversLoader ?? fetchCompanyOpsDrivers)();
      if (!mounted) return;
      for (final driver in drivers) {
        rememberCompanyDriverAgendaColor(
          companyAgendaDriverId(driver),
          (driver['agenda_color'] ?? driver['agendaColor'] ?? '').toString(),
        );
      }
      setState(() {
        _drivers = drivers;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kleuren laden mislukt.';
        _loading = false;
      });
    }
  }

  Future<void> _saveColor(Map<String, dynamic> driver, String color) async {
    final driverId = companyAgendaDriverId(driver);
    if (driverId.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await saveCompanyDriverAgendaColor(
        driver: driver,
        color: color,
        driverUpsert: widget.driverUpsert,
      );
      if (!mounted) return;
      setState(() => _saving = false);
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
        _error = 'Kleur bewaren mislukt.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: kCompanyDriverAgendaColorsPanelKey,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kCompanyAgendaColorLabel.of(_lang),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else if (_visibleDrivers.isEmpty)
              Text(kCompanyAgendaNoRegisteredDrivers.of(_lang))
            else
              for (final driver in _visibleDrivers) ...[
                Text(companyAgendaDriverName(driver)),
                const SizedBox(height: 6),
                CompanyDriverAgendaColorChips(
                  selected: _colorFor(driver),
                  enabled: !_saving,
                  usedBy: companyAgendaColorUsageByHex(
                    _drivers,
                    excludeDriverId: companyAgendaDriverId(driver),
                  ),
                  onSelect: (color) => _saveColor(driver, color),
                ),
                const SizedBox(height: 10),
              ],
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
}
