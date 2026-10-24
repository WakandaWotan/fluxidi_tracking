import 'package:fluxidi_tracking/customer_booking/official_address_lookup.dart';
import 'package:flutter/material.dart';
import '../app_strings.dart';
import '../limousine/limousine_address_field.dart';
import '../limousine/limousine_address_lookup.dart';
import 'company_address_field.dart';
import 'company_operational_base.dart';

/// Uses the existing address picker and the settings page's authenticated save.
/// A new key on company/profile hydration discards the previous tenant's draft.
class CompanyOperationalBaseEditor extends StatefulWidget {
  const CompanyOperationalBaseEditor({
    super.key,
    this.initialValue,
    required this.language,
    required this.onChanged,
    required this.onValidityChanged,
    this.lookup,
  });
  final CompanyOperationalBase? initialValue;
  final AppLanguage language;
  final ValueChanged<CompanyOperationalBase?> onChanged;
  final ValueChanged<bool> onValidityChanged;
  final LimousinePlaceLookup? lookup;

  @override
  State<CompanyOperationalBaseEditor> createState() =>
      _CompanyOperationalBaseEditorState();
}

class _CompanyOperationalBaseEditorState
    extends State<CompanyOperationalBaseEditor> {
  late final LimousineAddressFieldController controller;
  late final LimousinePlaceLookup lookup;
  bool valid = true;
  @override
  void initState() {
    super.initState();
    lookup = widget.lookup ?? OfficialAddressLookup();
    controller = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'operational_base',
    );
    final initial = widget.initialValue;
    if (initial?.isValid == true) {
      controller.acceptCopy(
        LimousineAddressValue(
          displayText: initial!.address,
          canonicalLabel: initial.address,
          lat: initial.latitude,
          lon: initial.longitude,
          acceptance: LimousineAddressAcceptance.selected,
        ),
      );
    }
    controller.addListener(_changed);
  }

  void _changed() {
    final value = controller.value;
    final empty = controller.textController.text.trim().isEmpty;
    final selected =
        value.acceptance == LimousineAddressAcceptance.selected &&
        value.hasCoordinates;
    valid = empty || selected;
    widget.onValidityChanged(valid);
    if (valid)
      widget.onChanged(
        empty
            ? const CompanyOperationalBase.cleared()
            : CompanyOperationalBase(
                address: value.canonicalLabel.isNotEmpty
                    ? value.canonicalLabel
                    : value.displayText,
                latitude: value.lat,
                longitude: value.lon,
              ),
      );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String t(String nl, String en, String fr, String es) =>
        LocalizedText(nl: nl, en: en, fr: fr, es: es).of(widget.language);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          t(
            'Vertrekbasis voor geplande ritten',
            'Departure base for scheduled rides',
            'Base de départ des courses planifiées',
            'Base de salida para viajes programados',
          ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          t(
            'Kies de echte vertrekbasis. Deze wordt gebruikt wanneer een voorafgaande rit geen vertrekpunt bepaalt.',
            'Choose the actual departure base. It is used when no preceding ride determines the origin.',
            'Choisissez la base réelle, utilisée lorsqu’aucune course précédente ne détermine le départ.',
            'Elige la base real, usada cuando ningún viaje anterior determina el origen.',
          ),
        ),
        const SizedBox(height: 8),
        CompanyAddressField(
          controller: controller,
          language: widget.language,
          label: t(
            'Adres vertrekbasis',
            'Departure base address',
            'Adresse de la base',
            'Dirección de la base',
          ),
          inputKey: const Key('company_operational_base_address'),
        ),
        if (!valid)
          Text(
            t(
              'Kies een volledig adres uit de voorstellen voordat je opslaat.',
              'Select a complete address suggestion before saving.',
              'Sélectionnez une adresse complète avant d’enregistrer.',
              'Selecciona una dirección completa antes de guardar.',
            ),
            key: const Key('company_operational_base_invalid'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
