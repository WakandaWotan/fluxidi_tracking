import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';

const Key kCompanyRoundtripChoiceKey = Key('company_roundtrip_choice');
const Key kCompanyRoundtripReturnFromKey = Key('company_roundtrip_return_from');
const Key kCompanyRoundtripReturnToKey = Key('company_roundtrip_return_to');

class CompanyRoundtripFields extends StatelessWidget {
  const CompanyRoundtripFields({
    super.key,
    required this.language,
    required this.choice,
    required this.onChoiceChanged,
    required this.returnPickup,
    required this.onReturnPickupChanged,
    required this.returnFrom,
    required this.returnTo,
    this.savedAddresses = const <CompanyCustomerAddress>[],
    this.returnDuration,
    this.onReturnDurationChanged,
    this.extra,
  });

  final AppLanguage language;
  final CompanyRoundtripChoice choice;
  final ValueChanged<CompanyRoundtripChoice> onChoiceChanged;
  final DateTime? returnPickup;
  final ValueChanged<DateTime?> onReturnPickupChanged;
  final LimousineAddressFieldController returnFrom;
  final LimousineAddressFieldController returnTo;
  final List<CompanyCustomerAddress> savedAddresses;
  final TextEditingController? returnDuration;
  final ValueChanged<String>? onReturnDurationChanged;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
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
        ),
        if (choice != CompanyRoundtripChoice.single) ...[
          const SizedBox(height: 8),
          CompanyDateTimeFields(
            fieldId: 'roundtrip_return',
            language: language,
            value: returnPickup,
            onChanged: onReturnPickupChanged,
            dateLabel: kCompanyRoundtripReturnWhen.of(language),
          ),
          const SizedBox(height: 12),
          CompanyAddressField(
            controller: returnFrom,
            label: kCompanyRoundtripReturnFrom.of(language),
            language: language,
            inputKey: kCompanyRoundtripReturnFromKey,
            savedAddresses: savedAddresses,
          ),
          CompanyAddressField(
            controller: returnTo,
            label: kCompanyRoundtripReturnTo.of(language),
            language: language,
            inputKey: kCompanyRoundtripReturnToKey,
            savedAddresses: savedAddresses,
          ),
          if (returnDuration != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: returnDuration,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: kCompanyRoundtripReturnDuration.of(language),
              ),
              onChanged: onReturnDurationChanged,
            ),
          ],
          if (choice == CompanyRoundtripChoice.continuousWait) ...[
            const SizedBox(height: 8),
            Text(
              kCompanyRoundtripOccupancyUnknown.of(language),
              style: Theme.of(context).textTheme.bodySmall,
              softWrap: true,
            ),
          ],
          if (extra != null) extra!,
        ],
      ],
    );
  }
}
