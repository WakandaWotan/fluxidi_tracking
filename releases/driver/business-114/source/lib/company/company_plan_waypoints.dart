// COMPANY-AGENDA-P0 — numbered waypoints on the existing planner state.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

const int kCompanyPlanMaxStops = 10;

const Key kCompanyPlanAddOutboundStopKey = Key('company_plan_add_outbound_stop');
const Key kCompanyPlanAddReturnStopKey = Key('company_plan_add_return_stop');
const Key kCompanyPlanStopCountKey = Key('company_plan_stop_count');

Key companyPlanStopFieldKey(String prefix, int index) =>
    Key('company_plan_stop_${prefix}_$index');

Key companyPlanStopRemoveKey(String prefix, int index) =>
    Key('company_plan_stop_remove_${prefix}_$index');

Key companyPlanStopMoveUpKey(String prefix, int index) =>
    Key('company_plan_stop_up_${prefix}_$index');

Key companyPlanStopMoveDownKey(String prefix, int index) =>
    Key('company_plan_stop_down_${prefix}_$index');

class CompanyPlanStopList {
  CompanyPlanStopList({
    required this.lookup,
    required this.fieldPrefix,
    required this.onChanged,
    this.language = 'nl',
  });

  final LimousinePlaceLookup lookup;
  final String fieldPrefix;
  final VoidCallback onChanged;
  String language;
  final List<LimousineAddressFieldController> items =
      <LimousineAddressFieldController>[];

  int get length => items.length;
  bool get canAdd => items.length < kCompanyPlanMaxStops;

  List<LimousineAddressValue> get values => [
        for (final item in items) item.value,
      ];

  List<String> get routeTexts => [
        for (final value in values)
          if (companyPlanAddressIsComplete(value)) value.routeText,
      ];

  LimousineAddressFieldController add() {
    if (!canAdd) {
      throw StateError('company_plan_stop_limit');
    }
    final controller = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: '${fieldPrefix}_${items.length}',
      language: language,
    );
    controller.addListener(onChanged);
    items.add(controller);
    onChanged();
    return controller;
  }

  void removeAt(int index) {
    if (index < 0 || index >= items.length) return;
    final controller = items.removeAt(index);
    controller.removeListener(onChanged);
    controller.dispose();
    onChanged();
  }

  void move(int from, int to) {
    if (from < 0 || from >= items.length || to < 0 || to >= items.length) {
      return;
    }
    if (from == to) return;
    final item = items.removeAt(from);
    items.insert(to, item);
    onChanged();
  }

  void clear() {
    for (final item in items) {
      item.removeListener(onChanged);
      item.dispose();
    }
    items.clear();
    onChanged();
  }

  void dispose() {
    for (final item in items) {
      item.removeListener(onChanged);
      item.dispose();
    }
    items.clear();
  }
}

bool companyPlanAddressIsComplete(LimousineAddressValue value) {
  return companyAddressIsComplete(value) && value.routeText.trim().isNotEmpty;
}

class CompanyPlanWaypointFields extends StatelessWidget {
  const CompanyPlanWaypointFields({
    super.key,
    required this.language,
    required this.stops,
    this.savedAddresses = const <CompanyCustomerAddress>[],
    this.addLabel,
    this.addKey = kCompanyPlanAddOutboundStopKey,
    this.showCount = true,
  });

  final AppLanguage language;
  final CompanyPlanStopList stops;
  final List<CompanyCustomerAddress> savedAddresses;
  final String? addLabel;
  final Key addKey;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stops.items.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CompanyAddressField(
                  controller: stops.items[i],
                  label: kCompanyAgendaStopLabel
                      .of(language)
                      .replaceAll('{n}', '${i + 1}'),
                  language: language,
                  inputKey: companyPlanStopFieldKey(stops.fieldPrefix, i),
                  savedAddresses: savedAddresses,
                ),
              ),
              Column(
                children: [
                  IconButton(
                    key: companyPlanStopMoveUpKey(stops.fieldPrefix, i),
                    tooltip: kCompanyAgendaStopLabel.of(language),
                    onPressed: i == 0 ? null : () => stops.move(i, i - 1),
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    key: companyPlanStopMoveDownKey(stops.fieldPrefix, i),
                    tooltip: kCompanyAgendaStopLabel.of(language),
                    onPressed: i >= stops.length - 1
                        ? null
                        : () => stops.move(i, i + 1),
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  IconButton(
                    key: companyPlanStopRemoveKey(stops.fieldPrefix, i),
                    tooltip: kCompanyAgendaCancel.of(language),
                    onPressed: () => stops.removeAt(i),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ],
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: addKey,
            onPressed: stops.canAdd ? () => stops.add() : null,
            icon: const Icon(Icons.add),
            label: Text(
              addLabel ?? kCompanyAgendaAddStop.of(language),
            ),
          ),
        ),
        if (showCount && stops.length > 0)
          Text(
            kCompanyAgendaStopCount
                .of(language)
                .replaceAll('{n}', '${stops.length}'),
            key: kCompanyPlanStopCountKey,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}
