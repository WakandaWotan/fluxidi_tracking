// COMPANY-AGENDA-P0 — one driver+vehicle combination per operational leg.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_assignment_choice_field.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_plan_assignment.dart';
import 'package:fluxidi_tracking/company/company_plan_media.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';

const String kCompanyCrewComboSeparator = '|';

const Key kCompanyAgendaPreferSameCrewKey = Key(
  'company_agenda_prefer_same_crew',
);
const Key kCompanyAgendaOutboundCrewKey = Key('company_agenda_outbound_crew');
const Key kCompanyAgendaReturnCrewKey = Key('company_agenda_return_crew');
const Key kCompanyCrewComboOpenKey = Key('company_crew_combo_open');
const Key kCompanyCrewComboSheetKey = Key('company_crew_combo_sheet');
const Key kCompanyCrewComboSearchKey = Key('company_crew_combo_search');
const Key kCompanyCrewComboListKey = Key('company_crew_combo_list');
const Key kCompanyCrewComboUnsuitableKey = Key('company_crew_combo_unsuitable');
const Key kCompanyCrewComboCloseKey = Key('company_crew_combo_close');
const Key kCompanyCrewComboSelectedCardKey = Key('company_crew_combo_selected');

const double kCompanyCrewComboPhoneBreakpoint = 600;

class CompanyCrewCombo {
  const CompanyCrewCombo({
    required this.driverId,
    required this.vehicleId,
    required this.driver,
    required this.vehicle,
    required this.presence,
  });

  final String driverId;
  final String vehicleId;
  final Map<String, dynamic> driver;
  final Map<String, dynamic> vehicle;
  final CompanyPlanPresence presence;

  String get id => companyCrewComboId(driverId, vehicleId);

  bool get isUnassigned => driverId.isEmpty && vehicleId.isEmpty;

  bool get suitable => presence.suitable;
}

String companyCrewComboId(String driverId, String vehicleId) {
  return '${driverId.trim()}$kCompanyCrewComboSeparator${vehicleId.trim()}';
}

({String driverId, String vehicleId}) parseCompanyCrewComboId(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return (driverId: '', vehicleId: '');
  final index = text.indexOf(kCompanyCrewComboSeparator);
  if (index < 0) return (driverId: text, vehicleId: '');
  return (
    driverId: text.substring(0, index),
    vehicleId: text.substring(index + 1),
  );
}

List<Map<String, dynamic>> companyCrewVehiclesForDriver({
  required Map<String, dynamic> driver,
  required List<Map<String, dynamic>> vehicles,
}) {
  final linked = companyAgendaDriverLinkedVehicleIds(driver);
  if (linked.isEmpty) return vehicles;
  return [
    for (final vehicle in vehicles)
      if (linked.contains(companyAgendaVehicleId(vehicle))) vehicle,
  ];
}

List<CompanyCrewCombo> companyPlanCrewCombos({
  required List<Map<String, dynamic>> drivers,
  required List<Map<String, dynamic>> vehicles,
  required CompanyPlanVehicleType type,
  required int passengers,
  bool whenNow = true,
  DateTime? rideStartUtc,
  DateTime? rideEndUtc,
  Map<String, CompanyDriverSchedule>? schedules,
}) {
  final typed = companyPlanVehiclesForType(
    vehicles: vehicles,
    type: type,
    passengers: passengers,
  );
  final combos = <CompanyCrewCombo>[];
  for (final driver in drivers) {
    final driverId = companyAgendaDriverId(driver);
    if (driverId.isEmpty || !companyAgendaDriverIsSuitable(driver)) continue;
    final candidates = companyCrewVehiclesForDriver(
      driver: driver,
      vehicles: typed,
    );
    if (candidates.isEmpty) {
      final presence = resolveCompanyPlanPresence(
        driver: driver,
        whenNow: whenNow,
        vehicles: const <Map<String, dynamic>>[],
        schedule: schedules?[driverId],
        rideStartUtc: rideStartUtc,
        rideEndUtc: rideEndUtc,
      );
      combos.add(
        CompanyCrewCombo(
          driverId: driverId,
          vehicleId: '',
          driver: driver,
          vehicle: const <String, dynamic>{},
          presence: presence,
        ),
      );
      continue;
    }
    for (final vehicle in candidates) {
      final vehicleId = companyAgendaVehicleId(vehicle);
      if (vehicleId.isEmpty) continue;
      if (!companyAgendaVehicleIsSuitable(vehicle, passengers: passengers)) {
        continue;
      }
      final presence = resolveCompanyPlanPresence(
        driver: driver,
        whenNow: whenNow,
        vehicles: [vehicle],
        schedule: schedules?[driverId],
        rideStartUtc: rideStartUtc,
        rideEndUtc: rideEndUtc,
      );
      combos.add(
        CompanyCrewCombo(
          driverId: driverId,
          vehicleId: vehicleId,
          driver: driver,
          vehicle: vehicle,
          presence: presence,
        ),
      );
    }
  }
  return combos;
}

bool companyPlanCrewComboAvailableOnBoth({
  required List<CompanyCrewCombo> outbound,
  required List<CompanyCrewCombo> inbound,
  required String driverId,
  required String vehicleId,
}) {
  if (driverId.trim().isEmpty && vehicleId.trim().isEmpty) return true;
  final first = companyPlanFindCrewCombo(
    combos: outbound,
    driverId: driverId,
    vehicleId: vehicleId,
  );
  final second = companyPlanFindCrewCombo(
    combos: inbound,
    driverId: driverId,
    vehicleId: vehicleId,
  );
  return first != null && first.suitable && second != null && second.suitable;
}

CompanyCrewCombo? companyPlanFindCrewCombo({
  required List<CompanyCrewCombo> combos,
  required String driverId,
  required String vehicleId,
}) {
  final wantDriver = driverId.trim();
  final wantVehicle = vehicleId.trim();
  for (final combo in combos) {
    if (combo.driverId == wantDriver && combo.vehicleId == wantVehicle) {
      return combo;
    }
  }
  if (wantDriver.isEmpty) return null;
  for (final combo in combos) {
    if (combo.driverId == wantDriver) return combo;
  }
  return null;
}

CompanyPlanAssignmentProposal proposeCompanyPlanCrewAssignment({
  required List<CompanyCrewCombo> combos,
  required bool userPicked,
  required String currentDriverId,
  required String currentVehicleId,
}) {
  if (combos.isEmpty) {
    return const CompanyPlanAssignmentProposal(driverId: '', vehicleId: '');
  }
  if (userPicked) {
    if (currentDriverId.trim().isEmpty && currentVehicleId.trim().isEmpty) {
      return const CompanyPlanAssignmentProposal(driverId: '', vehicleId: '');
    }
    final current = companyPlanFindCrewCombo(
      combos: combos,
      driverId: currentDriverId,
      vehicleId: currentVehicleId,
    );
    if (current != null && current.suitable) {
      return CompanyPlanAssignmentProposal(
        driverId: current.driverId,
        vehicleId: current.vehicleId,
      );
    }
  }
  final available = [
    for (final combo in combos)
      if (combo.suitable) combo,
  ];
  if (available.isEmpty) {
    return const CompanyPlanAssignmentProposal(driverId: '', vehicleId: '');
  }
  final chosen = available.first;
  return CompanyPlanAssignmentProposal(
    driverId: chosen.driverId,
    vehicleId: chosen.vehicleId,
  );
}

CompanyPlanAssignmentProposal proposeCompanyPlanReturnCrew({
  required List<CompanyCrewCombo> combos,
  required String outboundDriverId,
  required String outboundVehicleId,
  required bool preferSame,
  bool outboundAvailableForReturn = true,
}) {
  if (combos.isEmpty) {
    return const CompanyPlanAssignmentProposal(driverId: '', vehicleId: '');
  }
  final same = companyPlanFindCrewCombo(
    combos: combos,
    driverId: outboundDriverId,
    vehicleId: outboundVehicleId,
  );
  if (preferSame &&
      outboundAvailableForReturn &&
      same != null &&
      same.suitable) {
    return CompanyPlanAssignmentProposal(
      driverId: same.driverId,
      vehicleId: same.vehicleId,
    );
  }
  final other = [
    for (final combo in combos)
      if (combo.suitable &&
          (combo.driverId != outboundDriverId ||
              combo.vehicleId != outboundVehicleId))
        combo,
  ];
  if (other.isNotEmpty) {
    return CompanyPlanAssignmentProposal(
      driverId: other.first.driverId,
      vehicleId: other.first.vehicleId,
    );
  }
  if (same != null) {
    return CompanyPlanAssignmentProposal(
      driverId: same.driverId,
      vehicleId: same.vehicleId,
    );
  }
  return proposeCompanyPlanCrewAssignment(
    combos: combos,
    userPicked: false,
    currentDriverId: '',
    currentVehicleId: '',
  );
}

String companyPlanCompactPlace(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final first = text.split(',').first.trim();
  if (first.length <= 36) return first;
  return '${first.substring(0, 34).trim()}…';
}

String companyPlanCrewLegTitle({
  required String prefix,
  required String from,
  required String to,
  String fromFallback = 'A',
  String toFallback = 'B',
}) {
  final a = companyPlanCompactPlace(from);
  final b = companyPlanCompactPlace(to);
  return '$prefix ${a.isEmpty ? fromFallback : a} → ${b.isEmpty ? toFallback : b}';
}

class CompanyCrewComboGroup {
  const CompanyCrewComboGroup({
    required this.driverId,
    required this.driver,
    required this.combos,
  });

  final String driverId;
  final Map<String, dynamic> driver;
  final List<CompanyCrewCombo> combos;
}

List<CompanyCrewComboGroup> companyCrewComboGroups(
  List<CompanyCrewCombo> combos,
) {
  final order = <String>[];
  final grouped = <String, List<CompanyCrewCombo>>{};
  for (final combo in combos) {
    grouped
        .putIfAbsent(combo.driverId, () {
          order.add(combo.driverId);
          return <CompanyCrewCombo>[];
        })
        .add(combo);
  }
  return [
    for (final id in order)
      CompanyCrewComboGroup(
        driverId: id,
        driver: grouped[id]!.first.driver,
        combos: grouped[id]!,
      ),
  ];
}

List<CompanyCrewCombo> companyCrewCombosMatchingQuery(
  List<CompanyCrewCombo> combos,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return combos;
  return [
    for (final combo in combos)
      if (_crewComboSearchText(combo).contains(needle)) combo,
  ];
}

String _crewComboSearchText(CompanyCrewCombo combo) {
  return <String>[
    companyAgendaDriverName(combo.driver),
    companyPlanPublicDriverName(combo.driver, AppLanguage.nl),
    companyAgendaVehicleName(combo.vehicle),
    companyPlanPublicVehicleName(combo.vehicle, AppLanguage.nl),
    companyAgendaVehiclePlate(combo.vehicle),
  ].join(' ').toLowerCase();
}

CompanyCrewCombo companyCrewComboWithPresence(
  CompanyCrewCombo combo,
  CompanyPlanPresence presence,
) {
  return CompanyCrewCombo(
    driverId: combo.driverId,
    vehicleId: combo.vehicleId,
    driver: combo.driver,
    vehicle: combo.vehicle,
    presence: presence,
  );
}

String companyCrewComboLabel({
  required CompanyCrewCombo combo,
  required AppLanguage language,
  bool includePlate = false,
  DateTime? plannedLocal,
  bool durationKnown = true,
}) {
  final driver = companyPlanPublicDriverName(combo.driver, language);
  final vehicle = includePlate
      ? companyAgendaVehicleLabel(combo.vehicle)
      : companyPlanPublicVehicleName(combo.vehicle, language);
  final status = companyPlanPresenceLabel(
    combo.presence,
    language,
    plannedLocal: plannedLocal,
    durationKnown: durationKnown,
  );
  return '$driver · $status · $vehicle';
}

String companyPlanAssignmentRaceWarning({
  required String driverName,
  required String vehicleName,
  required String reason,
}) {
  return 'Rit bewaard, maar $driverName · $vehicleName kon niet worden toegewezen wegens $reason.';
}

String companyPlanAssignmentWarningReason(String code) {
  switch (code.trim()) {
    case 'assignment_overlap':
    case 'assignment_vehicle_overlap':
      return 'overlappende rit';
    case 'assignment_availability_unknown':
      return 'onbekende beschikbaarheid';
    case 'assignment_driver_on_trip':
      return 'chauffeur onderweg';
    case 'assignment_vehicle_busy':
      return 'voertuig bezet';
    default:
      return code.trim().isEmpty ? 'een toewijzingsconflict' : code.trim();
  }
}

List<CompanyAssignmentChoice> companyCrewComboChoices({
  required List<CompanyCrewCombo> combos,
  required AppLanguage language,
  required String unassignedLabel,
  bool includePlate = false,
  String tenantId = '',
  String companyId = '',
}) {
  return <CompanyAssignmentChoice>[
    CompanyAssignmentChoice(
      id: kCompanyAssignmentUnassignedId,
      label: unassignedLabel,
      searchText: unassignedLabel,
    ),
    for (final combo in combos)
      CompanyAssignmentChoice(
        id: combo.id,
        label: companyCrewComboLabel(
          combo: combo,
          language: language,
          includePlate: includePlate,
        ),
        subtitle: companyPlanPresenceLabel(combo.presence, language),
        searchText: <String>[
          companyAgendaDriverName(combo.driver),
          companyAgendaVehicleName(combo.vehicle),
          if (includePlate) companyAgendaVehiclePlate(combo.vehicle),
          combo.driverId,
          combo.vehicleId,
        ].join(' '),
        enabled: combo.suitable && companyAgendaDriverIsActive(combo.driver),
        leading: _CompanyCrewComboLook(combo: combo),
      ),
  ];
}

class CompanyCrewComboCard extends StatelessWidget {
  const CompanyCrewComboCard({
    super.key,
    required this.language,
    required this.title,
    required this.combo,
    this.plannedLocal,
    this.durationKnown = true,
    this.statusText,
    this.includePlate = false,
    this.selected = false,
    this.onTap,
  });

  final AppLanguage language;
  final String title;
  final CompanyCrewCombo? combo;
  final DateTime? plannedLocal;
  final bool durationKnown;
  final String? statusText;
  final bool includePlate;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = combo;
    final typeLabel = chosen == null
        ? ''
        : companyPlanVehicleTypeLabel(
            parseCompanyPlanVehicleType(
                  chosen.vehicle['vehicle_type']?.toString() ??
                      chosen.vehicle['vehicleType']?.toString() ??
                      '',
                ) ??
                CompanyPlanVehicleType.sedan,
            language,
          );
    final status = chosen == null
        ? kCompanyAgendaUnassignedLane.of(language)
        : (statusText ??
              companyPlanPresenceLabel(
                chosen.presence,
                language,
                plannedLocal: plannedLocal,
                durationKnown: durationKnown,
              ));
    final card = Card(
      margin: EdgeInsets.zero,
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title.trim().isNotEmpty) ...[
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
            ],
            if (chosen == null)
              Text(kCompanyAgendaUnassignedLane.of(language))
            else
              CompanyPlanAssignedCrew(
                snapshot: CompanyPlanAssignmentSnapshot(
                  driverId: chosen.driverId,
                  driverName: companyPlanPublicDriverName(
                    chosen.driver,
                    language,
                  ),
                  vehicleId: chosen.vehicleId,
                  vehicleName: includePlate
                      ? '$typeLabel · ${companyAgendaVehicleLabel(chosen.vehicle)}'
                      : '$typeLabel · ${companyPlanPublicVehicleName(chosen.vehicle, language)}',
                ),
                driver: chosen.driver,
                vehicle: chosen.vehicle,
              ),
            if (status.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: chosen == null
                      ? null
                      : companyPlanPresenceColor(chosen.presence.tone),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, child: card);
  }
}

class CompanyCrewComboPicker extends StatefulWidget {
  const CompanyCrewComboPicker({
    super.key,
    required this.language,
    required this.title,
    required this.combos,
    required this.selectedId,
    required this.onSelected,
    this.plannedLocal,
    this.durationKnown = true,
    this.includePlate = false,
    this.unassignedLabel,
    this.unsuitableChoices = const <CompanyAssignmentChoice>[],
  });

  final AppLanguage language;
  final String title;
  final List<CompanyCrewCombo> combos;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final DateTime? plannedLocal;
  final bool durationKnown;
  final bool includePlate;
  final String? unassignedLabel;
  final List<CompanyAssignmentChoice> unsuitableChoices;

  @override
  State<CompanyCrewComboPicker> createState() => _CompanyCrewComboPickerState();
}

class _CompanyCrewComboPickerState extends State<CompanyCrewComboPicker> {
  Future<void> _openChooser() async {
    final phone =
        MediaQuery.sizeOf(context).width < kCompanyCrewComboPhoneBreakpoint;
    if (phone) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: _CompanyCrewComboChooser(
              language: widget.language,
              title: widget.title,
              combos: widget.combos,
              selectedId: widget.selectedId,
              plannedLocal: widget.plannedLocal,
              includePlate: widget.includePlate,
              unassignedLabel: widget.unassignedLabel,
              unsuitableChoices: widget.unsuitableChoices,
              onSelected: (id) {
                Navigator.of(context).pop();
                widget.onSelected(id);
              },
            ),
          );
        },
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
            child: _CompanyCrewComboChooser(
              language: widget.language,
              title: widget.title,
              combos: widget.combos,
              selectedId: widget.selectedId,
              plannedLocal: widget.plannedLocal,
              includePlate: widget.includePlate,
              unassignedLabel: widget.unassignedLabel,
              unsuitableChoices: widget.unsuitableChoices,
              onSelected: (id) {
                Navigator.of(context).pop();
                widget.onSelected(id);
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = companyPlanFindCrewCombo(
      combos: widget.combos,
      driverId: parseCompanyCrewComboId(widget.selectedId).driverId,
      vehicleId: parseCompanyCrewComboId(widget.selectedId).vehicleId,
    );
    final unassigned =
        selected == null ||
        widget.selectedId == kCompanyAssignmentUnassignedId ||
        selected.isUnassigned;
    final openLabel = unassigned
        ? (widget.unassignedLabel ??
              kCompanyAgendaUnassignedLane.of(widget.language))
        : companyCrewComboLabel(
            combo: selected,
            language: widget.language,
            includePlate: false,
            plannedLocal: widget.plannedLocal,
            durationKnown: widget.durationKnown,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Semantics(
          key: kCompanyCrewComboOpenKey,
          button: true,
          container: true,
          excludeSemantics: true,
          label:
              '${widget.title}. $openLabel. ${kCompanyAgendaCrewChoose.of(widget.language)}',
          child: FocusableActionDetector(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _openChooser();
                  return null;
                },
              ),
            },
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openChooser,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: unassigned
                      ? Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.unassignedLabel ??
                                    kCompanyAgendaUnassignedLane.of(
                                      widget.language,
                                    ),
                              ),
                            ),
                            const Icon(Icons.expand_more),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: CompanyCrewComboCard(
                                key: kCompanyCrewComboSelectedCardKey,
                                language: widget.language,
                                title: '',
                                combo: selected,
                                plannedLocal: widget.plannedLocal,
                                durationKnown: widget.durationKnown,
                                includePlate: widget.includePlate,
                                selected: true,
                              ),
                            ),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompanyCrewComboChooser extends StatefulWidget {
  const _CompanyCrewComboChooser({
    required this.language,
    required this.title,
    required this.combos,
    required this.selectedId,
    required this.onSelected,
    required this.plannedLocal,
    required this.includePlate,
    required this.unassignedLabel,
    required this.unsuitableChoices,
  });

  final AppLanguage language;
  final String title;
  final List<CompanyCrewCombo> combos;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final DateTime? plannedLocal;
  final bool includePlate;
  final String? unassignedLabel;
  final List<CompanyAssignmentChoice> unsuitableChoices;

  @override
  State<_CompanyCrewComboChooser> createState() =>
      _CompanyCrewComboChooserState();
}

class _CompanyCrewComboChooserState extends State<_CompanyCrewComboChooser> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text;
    final suitable = [
      for (final combo in companyCrewCombosMatchingQuery(widget.combos, query))
        if (combo.suitable) combo,
    ];
    final blocked = [
      for (final combo in companyCrewCombosMatchingQuery(widget.combos, query))
        if (!combo.suitable) combo,
    ];
    final groups = companyCrewComboGroups(suitable);
    final extras = [
      for (final choice in widget.unsuitableChoices)
        if (query.trim().isEmpty ||
            choice.searchText.toLowerCase().contains(
              query.trim().toLowerCase(),
            ))
          choice,
    ];
    final unassignedLabel =
        widget.unassignedLabel ??
        kCompanyAgendaUnassignedLane.of(widget.language);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: Focus(
        child: Material(
          key: kCompanyCrewComboSheetKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    IconButton(
                      key: kCompanyCrewComboCloseKey,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: kCompanyCrewComboSearchKey,
                  controller: _search,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: kCompanyAgendaCrewSearch.of(widget.language),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  key: kCompanyCrewComboListKey,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                  itemCount:
                      1 +
                      groups.length +
                      (blocked.isEmpty && extras.isEmpty ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ListTile(
                        key: const Key('company_agenda_unassigned_lane'),
                        leading: const Icon(Icons.person_off_outlined),
                        title: Text(unassignedLabel),
                        selected:
                            widget.selectedId ==
                                kCompanyAssignmentUnassignedId ||
                            widget.selectedId.isEmpty,
                        onTap: () =>
                            widget.onSelected(kCompanyAssignmentUnassignedId),
                      );
                    }
                    if (index <= groups.length) {
                      return _CompanyCrewComboGroupTile(
                        group: groups[index - 1],
                        language: widget.language,
                        selectedId: widget.selectedId,
                        plannedLocal: widget.plannedLocal,
                        includePlate: widget.includePlate,
                        onSelected: widget.onSelected,
                      );
                    }
                    return _CompanyCrewUnsuitableSection(
                      language: widget.language,
                      blocked: blocked,
                      extras: extras,
                      plannedLocal: widget.plannedLocal,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyCrewComboGroupTile extends StatelessWidget {
  const _CompanyCrewComboGroupTile({
    required this.group,
    required this.language,
    required this.selectedId,
    required this.plannedLocal,
    required this.includePlate,
    required this.onSelected,
  });

  final CompanyCrewComboGroup group;
  final AppLanguage language;
  final String selectedId;
  final DateTime? plannedLocal;
  final bool includePlate;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final name = companyPlanPublicDriverName(group.driver, language);
    if (group.combos.length == 1) {
      return _CompanyCrewComboOptionTile(
        combo: group.combos.first,
        language: language,
        selected: group.combos.first.id == selectedId,
        plannedLocal: plannedLocal,
        includePlate: includePlate,
        onSelected: onSelected,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: CircleAvatar(child: Text(companyAgendaInitials(name))),
          title: Text(name),
          subtitle: Text(
            kCompanyAgendaCrewVehicleCount
                .of(language)
                .replaceAll('{count}', '${group.combos.length}'),
          ),
        ),
        for (final combo in group.combos)
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: _CompanyCrewComboOptionTile(
              combo: combo,
              language: language,
              selected: combo.id == selectedId,
              plannedLocal: plannedLocal,
              includePlate: includePlate,
              onSelected: onSelected,
              compactVehicle: true,
            ),
          ),
      ],
    );
  }
}

class _CompanyCrewComboOptionTile extends StatelessWidget {
  const _CompanyCrewComboOptionTile({
    required this.combo,
    required this.language,
    required this.selected,
    required this.plannedLocal,
    required this.includePlate,
    required this.onSelected,
    this.compactVehicle = false,
  });

  final CompanyCrewCombo combo;
  final AppLanguage language;
  final bool selected;
  final DateTime? plannedLocal;
  final bool includePlate;
  final ValueChanged<String> onSelected;
  final bool compactVehicle;

  @override
  Widget build(BuildContext context) {
    final driver = companyPlanPublicDriverName(combo.driver, language);
    final vehicle = companyPlanPublicVehicleName(combo.vehicle, language);
    final type = companyPlanVehicleTypeLabel(
      parseCompanyPlanVehicleType(
            combo.vehicle['vehicle_type']?.toString() ??
                combo.vehicle['vehicleType']?.toString() ??
                '',
          ) ??
          CompanyPlanVehicleType.sedan,
      language,
    );
    final status = companyPlanPresenceLabel(
      combo.presence,
      language,
      plannedLocal: plannedLocal,
      durationKnown: true,
    );
    final plate = includePlate ? companyAgendaVehiclePlate(combo.vehicle) : '';
    return Semantics(
      button: true,
      selected: selected,
      enabled: combo.suitable,
      label: compactVehicle
          ? '$vehicle. $status'
          : '$driver. $vehicle. $status',
      child: ListTile(
        key: Key('company_crew_combo_${combo.id}'),
        enabled: combo.suitable,
        selected: selected,
        leading: compactVehicle
            ? const Icon(Icons.directions_car_outlined)
            : _CompanyCrewComboLook(combo: combo),
        title: Text(compactVehicle ? vehicle : driver),
        subtitle: Text(
          compactVehicle
              ? '$type${plate.isEmpty ? '' : ' · $plate'} · $status'
              : '$vehicle · $type · $status',
        ),
        onTap: combo.suitable ? () => onSelected(combo.id) : null,
      ),
    );
  }
}

class _CompanyCrewUnsuitableSection extends StatelessWidget {
  const _CompanyCrewUnsuitableSection({
    required this.language,
    required this.blocked,
    required this.extras,
    required this.plannedLocal,
  });

  final AppLanguage language;
  final List<CompanyCrewCombo> blocked;
  final List<CompanyAssignmentChoice> extras;
  final DateTime? plannedLocal;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: kCompanyCrewComboUnsuitableKey,
      initiallyExpanded: false,
      title: Text(kCompanyAgendaUnsuitableDrivers.of(language)),
      children: [
        for (final combo in blocked)
          ListTile(
            enabled: false,
            leading: _CompanyCrewComboLook(combo: combo),
            title: Text(companyPlanPublicDriverName(combo.driver, language)),
            subtitle: Text(
              companyPlanPresenceLabel(
                combo.presence,
                language,
                plannedLocal: plannedLocal,
              ),
            ),
          ),
        for (final choice in extras)
          ListTile(
            enabled: false,
            leading: choice.leading,
            title: Text(choice.label),
            subtitle: choice.subtitle.trim().isEmpty
                ? null
                : Text(choice.subtitle),
          ),
      ],
    );
  }
}

class _CompanyCrewComboLook extends StatelessWidget {
  const _CompanyCrewComboLook({required this.combo});

  final CompanyCrewCombo combo;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: companyPlanPresenceColor(combo.presence.tone),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        CompanyPlanDriverAvatar(
          media: resolveCompanyPlanDriverMedia(driver: combo.driver),
          radius: 12,
        ),
      ],
    );
  }
}
