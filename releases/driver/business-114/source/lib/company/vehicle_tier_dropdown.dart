/// Dropdown model for a stored vehicle tier that may not be in [enabledTiers].
///
/// The fleet record is left unchanged. A stored value such as `*` is shown as
/// an extra unique option so [DropdownButton] can find exactly one match.
class VehicleTierDropdownOption {
  const VehicleTierDropdownOption({required this.id, required this.label});

  final String id;
  final String label;
}

class VehicleTierDropdownModel {
  const VehicleTierDropdownModel({required this.value, required this.items});

  final String? value;
  final List<VehicleTierDropdownOption> items;
}

VehicleTierDropdownModel buildVehicleTierDropdownModel({
  required List<({String id, String label})> enabledTiers,
  required String storedTierId,
  required String Function(String id) unknownTierLabel,
}) {
  final seen = <String>{};
  final items = <VehicleTierDropdownOption>[];

  void add(String id, String label) {
    final key = id.trim();
    if (key.isEmpty || seen.contains(key)) return;
    seen.add(key);
    items.add(VehicleTierDropdownOption(id: key, label: label));
  }

  for (final tier in enabledTiers) {
    add(tier.id, tier.label);
  }

  final stored = storedTierId.trim();
  if (stored.isNotEmpty && !seen.contains(stored)) {
    add(stored, unknownTierLabel(stored));
  }

  if (items.isEmpty) {
    return const VehicleTierDropdownModel(value: null, items: <VehicleTierDropdownOption>[]);
  }

  final value = stored.isEmpty
      ? items.first.id
      : (seen.contains(stored) ? stored : items.first.id);
  return VehicleTierDropdownModel(value: value, items: List<VehicleTierDropdownOption>.unmodifiable(items));
}
