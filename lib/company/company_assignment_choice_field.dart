// COMPANY-CUSTOMER-OPS-P0 — searchable driver/vehicle assignment choices.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';

enum CompanyAssignmentChoiceKind { driver, vehicle }

const String kCompanyAssignmentUnassignedId = '';

Key companyAssignmentChoiceKey(CompanyAssignmentChoiceKind kind, String id) {
  final suffix = id.trim().isEmpty ? 'unassigned' : id.trim();
  return Key('company_agenda_choice_${kind.name}_$suffix');
}

class CompanyAssignmentChoice {
  const CompanyAssignmentChoice({
    required this.id,
    required this.label,
    required this.searchText,
    this.subtitle = '',
    this.enabled = true,
    this.leading,
  });

  final String id;
  final String label;
  final String searchText;
  final String subtitle;
  final bool enabled;
  final Widget? leading;

  bool get isUnassigned => id.trim().isEmpty;
}

List<CompanyAssignmentChoice> companyAssignmentFilterChoices(
  List<CompanyAssignmentChoice> choices,
  String query,
) {
  final needle = query.trim().toLowerCase();
  final unassigned = <CompanyAssignmentChoice>[];
  final rest = <CompanyAssignmentChoice>[];
  for (final choice in choices) {
    if (choice.isUnassigned) {
      unassigned.add(choice);
    } else {
      rest.add(choice);
    }
  }
  if (needle.isEmpty) return <CompanyAssignmentChoice>[...unassigned, ...rest];
  return <CompanyAssignmentChoice>[
    ...unassigned,
    ...rest.where((choice) => choice.searchText.toLowerCase().contains(needle)),
  ];
}

String companyAgendaAssignmentExceptionText(
  CompanyAgendaException error,
  AppLanguage language,
) {
  return switch (error.code) {
    'assignment_overlap' => kCompanyAgendaOverlap.of(language),
    'assignment_availability_unknown' => kCompanyAgendaAvailabilityUnknown.of(
      language,
    ),
    'price_changed' => kCompanyAgendaPriceChanged.of(language),
    _ => kCompanyAgendaSaveFailed.of(language),
  };
}

String? companyAgendaAssignmentOverlapText(
  CompanyAgendaOverlapCheck check,
  AppLanguage language,
) {
  if (!check.hasConflict) return null;
  return switch (check.code) {
    'assignment_overlap' => kCompanyAgendaOverlapPreview.of(language),
    'assignment_availability_unknown' => kCompanyAgendaAvailabilityUnknown.of(
      language,
    ),
    _ => kCompanyAgendaOverlapPreview.of(language),
  };
}

String? companyAgendaAssignmentChoicesStatus({
  required AppLanguage language,
  required bool loading,
  String? error,
  required List<Map<String, dynamic>> drivers,
  required List<Map<String, dynamic>> vehicles,
  required int passengers,
}) {
  if (loading) return kCompanyAgendaChoicesLoading.of(language);
  if (error != null && error.trim().isNotEmpty) return error;
  final hasRegisteredDrivers = drivers.any(
    (driver) => companyAgendaDriverId(driver).isNotEmpty,
  );
  if (!hasRegisteredDrivers) {
    return kCompanyAgendaNoRegisteredDrivers.of(language);
  }
  if (!drivers.any(companyAgendaDriverIsSuitable)) {
    return kCompanyAgendaNoSuitableDrivers.of(language);
  }
  final hasRegisteredVehicles = vehicles.any(
    (vehicle) => companyAgendaVehicleId(vehicle).isNotEmpty,
  );
  if (!hasRegisteredVehicles) {
    return kCompanyAgendaNoRegisteredVehicles.of(language);
  }
  if (!vehicles.any(
    (vehicle) =>
        companyAgendaVehicleIsSuitable(vehicle, passengers: passengers),
  )) {
    return kCompanyAgendaNoSuitableVehicles.of(language);
  }
  return null;
}

List<CompanyAssignmentChoice> companyAssignmentDriverChoices({
  required List<Map<String, dynamic>> drivers,
  required AppLanguage language,
  required String unassignedLabel,
}) {
  return <CompanyAssignmentChoice>[
    CompanyAssignmentChoice(
      id: kCompanyAssignmentUnassignedId,
      label: unassignedLabel,
      searchText: unassignedLabel,
    ),
    for (final driver in drivers)
      if (companyAgendaDriverId(driver).isNotEmpty)
        CompanyAssignmentChoice(
          id: companyAgendaDriverId(driver),
          label: _driverChoiceLabel(driver, language),
          searchText: <String>[
            companyAgendaDriverName(driver),
            companyAgendaDriverId(driver),
          ].join(' '),
          enabled: companyAgendaDriverIsActive(driver),
          leading: _CompanyAssignmentDriverLook(driver: driver),
        ),
  ];
}

List<CompanyAssignmentChoice> companyAssignmentVehicleChoices({
  required List<Map<String, dynamic>> vehicles,
  required AppLanguage language,
  required String unassignedLabel,
  required int passengers,
}) {
  return <CompanyAssignmentChoice>[
    CompanyAssignmentChoice(
      id: kCompanyAssignmentUnassignedId,
      label: unassignedLabel,
      searchText: unassignedLabel,
    ),
    for (final vehicle in vehicles)
      if (companyAgendaVehicleId(vehicle).isNotEmpty)
        CompanyAssignmentChoice(
          id: companyAgendaVehicleId(vehicle),
          label: _vehicleChoiceTitle(vehicle, language, passengers),
          subtitle: companyAgendaVehiclePlate(vehicle),
          searchText: <String>[
            companyAgendaVehicleName(vehicle),
            companyAgendaVehiclePlate(vehicle),
            companyAgendaVehicleLabel(vehicle),
            companyAgendaVehicleId(vehicle),
          ].join(' '),
          enabled: companyAgendaVehicleIsSuitable(
            vehicle,
            passengers: passengers,
          ),
        ),
  ];
}

String _driverChoiceLabel(Map<String, dynamic> driver, AppLanguage language) {
  final name = companyAgendaDriverName(driver);
  if (!companyAgendaDriverIsActive(driver)) {
    return '$name · ${kCompanyAgendaDriverInactive.of(language)}';
  }
  return name;
}

String _vehicleChoiceTitle(
  Map<String, dynamic> vehicle,
  AppLanguage language,
  int passengers,
) {
  final name = companyAgendaVehicleName(vehicle);
  final plate = companyAgendaVehiclePlate(vehicle);
  final label = name.isNotEmpty ? name : companyAgendaVehicleLabel(vehicle);
  if (!companyAgendaVehicleIsActive(vehicle)) {
    return '$label · ${kCompanyAgendaDriverInactive.of(language)}';
  }
  final capacity = companyAgendaVehicleCapacity(vehicle);
  if (capacity > 0 && capacity < passengers) {
    return '$label · te klein voor $passengers';
  }
  if (name.isNotEmpty && plate.isNotEmpty) return '$name · $plate';
  return label;
}

class CompanyAssignmentSearchField extends StatefulWidget {
  const CompanyAssignmentSearchField({
    super.key,
    required this.kind,
    required this.language,
    required this.label,
    required this.selectedId,
    required this.choices,
    required this.onSelected,
    this.enabled = true,
    this.statusText,
  });

  final CompanyAssignmentChoiceKind kind;
  final AppLanguage language;
  final String label;
  final String selectedId;
  final List<CompanyAssignmentChoice> choices;
  final ValueChanged<String> onSelected;
  final bool enabled;
  final String? statusText;

  @override
  State<CompanyAssignmentSearchField> createState() =>
      _CompanyAssignmentSearchFieldState();
}

class _CompanyAssignmentSearchFieldState
    extends State<CompanyAssignmentSearchField> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _open = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _text.text = _selectedLabel;
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant CompanyAssignmentSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_open &&
        (oldWidget.selectedId != widget.selectedId ||
            oldWidget.choices != widget.choices)) {
      _text.text = _selectedLabel;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  CompanyAssignmentChoice? get _selected {
    final id = widget.selectedId.trim();
    for (final choice in widget.choices) {
      if (choice.id == id) return choice;
    }
    return null;
  }

  String get _selectedLabel =>
      _selected?.label ??
      (widget.selectedId.trim().isEmpty
          ? (widget.choices.isEmpty ? '' : widget.choices.first.label)
          : widget.selectedId);

  String get _activeFilter {
    final typed = _filter.trim();
    if (typed.isEmpty || typed == _selectedLabel.trim()) return '';
    return typed;
  }

  List<CompanyAssignmentChoice> get _visible =>
      companyAssignmentFilterChoices(widget.choices, _activeFilter);

  void _onFocus() {
    if (!widget.enabled) return;
    if (_focus.hasFocus) {
      setState(() => _open = true);
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
      return;
    }
    _closeAndRevert();
  }

  void _closeAndRevert() {
    if (!mounted) return;
    setState(() {
      _open = false;
      _filter = '';
      _text.text = _selectedLabel;
    });
  }

  void _select(CompanyAssignmentChoice choice) {
    widget.onSelected(choice.id);
    setState(() {
      _open = false;
      _filter = '';
      _text.text = choice.label;
    });
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: (_) {
        if (_open) _closeAndRevert();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            focusNode: _focus,
            enabled: widget.enabled,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: widget.label,
              suffixIcon: IconButton(
                tooltip: widget.label,
                onPressed: widget.enabled
                    ? () {
                        if (_open) {
                          _closeAndRevert();
                        } else {
                          _focus.requestFocus();
                        }
                      }
                    : null,
                icon: Icon(
                  _open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                ),
              ),
            ),
            onTap: widget.enabled
                ? () => setState(() => _open = true)
                : null,
            onChanged: (value) {
              if (!widget.enabled) return;
              setState(() {
                _open = true;
                _filter = value;
              });
            },
          ),
          if (widget.statusText != null && widget.statusText!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                widget.statusText!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (_open) ...[
            const SizedBox(height: 4),
            Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: _visible.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('—'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final choice in _visible)
                            ListTile(
                              key: companyAssignmentChoiceKey(
                                widget.kind,
                                choice.id,
                              ),
                              enabled: choice.enabled,
                              leading: choice.leading,
                              title: Text(choice.label),
                              subtitle: choice.subtitle.trim().isEmpty
                                  ? null
                                  : Text(choice.subtitle),
                              onTap: choice.enabled
                                  ? () => _select(choice)
                                  : null,
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompanyAssignmentDriverLook extends StatelessWidget {
  const _CompanyAssignmentDriverLook({required this.driver});

  final Map<String, dynamic> driver;

  @override
  Widget build(BuildContext context) {
    final look = companyAgendaDriverLook(driver);
    final photo = look.photoUrl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: look.color,
          backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
          onBackgroundImageError: photo.isEmpty ? null : (_, _) {},
          child: photo.isEmpty
              ? Text(
                  look.initials,
                  style: TextStyle(
                    color: companyAgendaOnColor(look.color),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: look.color,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
        ),
      ],
    );
  }
}
