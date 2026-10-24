import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/vehicle_tier_dropdown.dart';

void main() {
  const enabled = <({String id, String label})>[
    (id: 'comfort', label: 'Comfort'),
    (id: 'private', label: 'Private'),
    (id: 'premium', label: 'Premium'),
  ];

  String unknownLabel(String id) => id == '*' ? 'Unset (*)' : 'Stored ($id)';

  test('stored star stays selected and gets exactly one extra item', () {
    final model = buildVehicleTierDropdownModel(
      enabledTiers: enabled,
      storedTierId: '*',
      unknownTierLabel: unknownLabel,
    );
    expect(model.value, '*');
    expect(model.items.where((item) => item.id == '*'), hasLength(1));
    expect(model.items.map((item) => item.id).toSet(), hasLength(model.items.length));
    expect(model.items.any((item) => item.id == 'comfort'), isTrue);
  });

  test('known stored tier does not invent a comfort overwrite', () {
    final model = buildVehicleTierDropdownModel(
      enabledTiers: enabled,
      storedTierId: 'premium',
      unknownTierLabel: unknownLabel,
    );
    expect(model.value, 'premium');
    expect(model.items.any((item) => item.id == '*'), isFalse);
  });

  test('duplicate enabled ids collapse to one item', () {
    final model = buildVehicleTierDropdownModel(
      enabledTiers: <({String id, String label})>[
        (id: 'comfort', label: 'Comfort'),
        (id: 'comfort', label: 'Comfort copy'),
        (id: 'premium', label: 'Premium'),
      ],
      storedTierId: 'comfort',
      unknownTierLabel: unknownLabel,
    );
    expect(model.items.where((item) => item.id == 'comfort'), hasLength(1));
    expect(model.value, 'comfort');
  });

  test('empty stored value uses the first enabled tier for a new vehicle', () {
    final model = buildVehicleTierDropdownModel(
      enabledTiers: enabled,
      storedTierId: '',
      unknownTierLabel: unknownLabel,
    );
    expect(model.value, 'comfort');
    expect(model.items.any((item) => item.id == '*'), isFalse);
  });
}
