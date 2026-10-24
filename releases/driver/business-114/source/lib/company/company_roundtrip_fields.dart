import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_plan_airport_cards.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';

const Key kCompanyRoundtripChoiceKey = Key('company_roundtrip_choice');
const Key kCompanyRoundtripReturnFromKey = Key('company_roundtrip_return_from');
const Key kCompanyRoundtripReturnToKey = Key('company_roundtrip_return_to');
const Key kCompanyRoundtripWaitKey = Key('company_roundtrip_wait');
const Key kCompanyRoundtripAddStopKey = Key('company_roundtrip_add_stop');
const Key kCompanyRoundtripWaitManualKey = Key('company_roundtrip_wait_manual');

Key companyRoundtripWaitPresetKey(int minutes) {
  return Key('company_roundtrip_wait_$minutes');
}

class CompanyRoundtripFields extends StatefulWidget {
  const CompanyRoundtripFields({
    super.key,
    required this.language,
    required this.choice,
    required this.onChoiceChanged,
    required this.returnPickup,
    required this.onReturnPickupChanged,
    required this.returnTo,
    this.savedAddresses = const <CompanyCustomerAddress>[],
    this.waitMin = 0,
    this.onWaitMinChanged,
    this.returnStops,
    this.extra,
    this.showReturnTo = true,
    this.showChoice = true,
    this.showReturnWhen = true,
    this.showWait = true,
    this.returnFromText = '',
    this.returnToText = '',
  });

  final AppLanguage language;
  final CompanyRoundtripChoice choice;
  final ValueChanged<CompanyRoundtripChoice> onChoiceChanged;
  final DateTime? returnPickup;
  final ValueChanged<DateTime?> onReturnPickupChanged;
  final LimousineAddressFieldController returnTo;
  final List<CompanyCustomerAddress> savedAddresses;
  final int waitMin;
  final ValueChanged<int>? onWaitMinChanged;
  final Widget? returnStops;
  final Widget? extra;
  final bool showReturnTo;
  final bool showChoice;
  final bool showReturnWhen;
  final bool showWait;
  final String returnFromText;
  final String returnToText;

  @override
  State<CompanyRoundtripFields> createState() => _CompanyRoundtripFieldsState();
}

class _CompanyRoundtripFieldsState extends State<CompanyRoundtripFields> {
  late final TextEditingController _waitManual;

  @override
  void initState() {
    super.initState();
    final wait = widget.waitMin > 0 ? widget.waitMin : 0;
    _waitManual = TextEditingController(
      text: kCompanyPlanAirportWaitPresets.contains(wait) || wait <= 0
          ? ''
          : '$wait',
    );
  }

  @override
  void didUpdateWidget(covariant CompanyRoundtripFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wait = widget.waitMin;
    final text = kCompanyPlanAirportWaitPresets.contains(wait) || wait <= 0
        ? ''
        : '$wait';
    if (_waitManual.text != text && !_waitManual.selection.isValid) {
      _waitManual.text = text;
    }
  }

  @override
  void dispose() {
    _waitManual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = widget.choice == CompanyRoundtripChoice.continuousWait;
    final split = widget.choice == CompanyRoundtripChoice.splitNoWait;
    final wait = widget.waitMin > 0 ? widget.waitMin : 45;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showChoice)
          CompanyRoundtripChoiceControl(
            language: widget.language,
            choice: widget.choice,
            onChoiceChanged: widget.onChoiceChanged,
          ),
        if (widget.choice != CompanyRoundtripChoice.single) ...[
          if (widget.returnFromText.trim().isNotEmpty ||
              widget.returnToText.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              kCompanyAgendaReturnSummary
                  .of(widget.language)
                  .replaceAll(
                    '{from}',
                    widget.returnFromText.trim().isEmpty
                        ? 'B'
                        : widget.returnFromText.trim(),
                  )
                  .replaceAll(
                    '{to}',
                    widget.returnToText.trim().isEmpty
                        ? 'A'
                        : widget.returnToText.trim(),
                  ),
              key: kCompanyAgendaReturnSummaryKey,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
          if (widget.showReturnTo) ...[
            const SizedBox(height: 8),
            CompanyAddressField(
              controller: widget.returnTo,
              label: kCompanyRoundtripReturnToPlace.of(widget.language),
              language: widget.language,
              inputKey: kCompanyRoundtripReturnToKey,
              savedAddresses: widget.savedAddresses,
            ),
          ],
          if (widget.returnStops != null) ...[
            const SizedBox(height: 8),
            widget.returnStops!,
          ],
        ],
        if (widget.showWait && waiting)
          CompanyPlanWaitChips(
            language: widget.language,
            waitMin: wait,
            manual: _waitManual,
            onWaitMinChanged: widget.onWaitMinChanged,
          ),
        if (widget.showReturnWhen && split) ...[
          const SizedBox(height: 8),
          CompanyDateTimeFields(
            fieldId: 'roundtrip_return',
            language: widget.language,
            value: widget.returnPickup,
            onChanged: widget.onReturnPickupChanged,
            leadingLabel: kCompanyRoundtripReturn.of(widget.language),
            timeLabel: kCompanyFormTime.of(widget.language),
          ),
        ],
        if (widget.extra != null) widget.extra!,
      ],
    );
  }
}

class CompanyRoundtripChoiceControl extends StatelessWidget {
  const CompanyRoundtripChoiceControl({
    super.key,
    required this.language,
    required this.choice,
    required this.onChoiceChanged,
  });

  final AppLanguage language;
  final CompanyRoundtripChoice choice;
  final ValueChanged<CompanyRoundtripChoice> onChoiceChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        if (wide) {
          return SegmentedButton<CompanyRoundtripChoice>(
            key: kCompanyRoundtripChoiceKey,
            segments: [
              for (final option in CompanyRoundtripChoice.values)
                ButtonSegment<CompanyRoundtripChoice>(
                  value: option,
                  label: Text(
                    key: Key('company_roundtrip_${option.name}'),
                    companyRoundtripChoiceLabel(option).of(language),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            selected: <CompanyRoundtripChoice>{choice},
            onSelectionChanged: (next) {
              if (next.isEmpty) return;
              onChoiceChanged(next.first);
            },
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            showSelectedIcon: false,
          );
        }
        return Column(
          key: kCompanyRoundtripChoiceKey,
          children: [
            for (final option in CompanyRoundtripChoice.values)
              RadioListTile<CompanyRoundtripChoice>(
                key: Key('company_roundtrip_${option.name}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  companyRoundtripChoiceLabel(option).of(language),
                  softWrap: true,
                ),
                value: option,
                groupValue: choice,
                onChanged: (next) {
                  if (next != null) onChoiceChanged(next);
                },
              ),
          ],
        );
      },
    );
  }
}

class CompanyPlanWaitChips extends StatelessWidget {
  const CompanyPlanWaitChips({
    super.key,
    required this.language,
    required this.waitMin,
    required this.manual,
    this.onWaitMinChanged,
  });

  final AppLanguage language;
  final int waitMin;
  final TextEditingController manual;
  final ValueChanged<int>? onWaitMinChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          kCompanyAgendaWaitTime.of(language),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          key: kCompanyRoundtripWaitKey,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in kCompanyPlanAirportWaitPresets)
              ChoiceChip(
                key: companyRoundtripWaitPresetKey(minutes),
                label: Text('$minutes min'),
                selected: waitMin == minutes,
                onSelected: (_) => onWaitMinChanged?.call(minutes),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: kCompanyRoundtripWaitManualKey,
          controller: manual,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: kCompanyAgendaWaitManual.of(language),
          ),
          onChanged: (text) {
            final parsed = int.tryParse(text.trim());
            if (parsed != null && parsed > 0 && parsed <= 240) {
              onWaitMinChanged?.call(parsed);
            }
          },
        ),
        const SizedBox(height: 8),
        Text(
          kCompanyAgendaDriverWaitsAbout
              .of(language)
              .replaceAll('{min}', '$waitMin'),
          key: const Key('company_roundtrip_wait_summary'),
        ),
      ],
    );
  }
}
