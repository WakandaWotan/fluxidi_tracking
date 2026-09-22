import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_profile/customer_stored_address.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';

const Key kCustomerProfileHomeAddressFieldKey = ValueKey<String>(
  'customer_profile_home_address',
);
const Key kCustomerProfileHomeHouseNumberKey = ValueKey<String>(
  'customer_profile_home_house_number',
);
const Key kCustomerProfileHomeAdditionKey = ValueKey<String>(
  'customer_profile_home_addition',
);
const Key kCustomerProfileHomeBusKey = ValueKey<String>(
  'customer_profile_home_bus',
);
const Key kCustomerProfileHomeConfirmHintKey = ValueKey<String>(
  'customer_profile_home_confirm_hint',
);
const Key kCustomerProfileBillingAddressFieldKey = ValueKey<String>(
  'customer_profile_billing_address',
);
const Key kCustomerProfileUseHomeForBillingKey = ValueKey<String>(
  'customer_profile_use_home_for_billing',
);

/// Compact address search that reuses the booking-flow Mapbox field.
class CustomerProfileAddressEditor extends StatefulWidget {
  const CustomerProfileAddressEditor({
    super.key,
    required this.fieldId,
    required this.palette,
    required this.language,
    required this.value,
    required this.onChanged,
    this.lookup,
    this.requireExactHouse = false,
    this.contextCountry,
    this.contextPostalCode,
    this.contextLocality,
  });

  final String fieldId;
  final CustomerThemePalette palette;
  final AppLanguage language;
  final CustomerStoredAddress value;
  final ValueChanged<CustomerStoredAddress> onChanged;
  final LimousinePlaceLookup? lookup;
  final bool requireExactHouse;
  final String? contextCountry;
  final String? contextPostalCode;
  final String? contextLocality;

  @override
  State<CustomerProfileAddressEditor> createState() =>
      _CustomerProfileAddressEditorState();
}

class _CustomerProfileAddressEditorState
    extends State<CustomerProfileAddressEditor> {
  late final LimousinePlaceLookup _lookup;
  late final LimousineAddressFieldController _controller;
  late final TextEditingController _houseCtrl;
  late final TextEditingController _additionCtrl;
  late final TextEditingController _busCtrl;
  late final FocusNode _focus;
  bool _syncing = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (widget.language) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.en:
      default:
        return en;
    }
  }

  @override
  void initState() {
    super.initState();
    _lookup = widget.lookup ?? LimousinePlaceLookup(country: 'be');
    _controller = LimousineAddressFieldController(
      lookup: _lookup,
      fieldId: widget.fieldId,
      language: widget.language.name,
      debounce: const Duration(milliseconds: 350),
    );
    _houseCtrl = TextEditingController(text: widget.value.houseNumber);
    _additionCtrl = TextEditingController(text: widget.value.houseAddition);
    _busCtrl = TextEditingController(text: widget.value.bus);
    _focus = FocusNode();
    _bindContext();
    if (!widget.value.isEmpty) {
      _controller.acceptCopy(
        LimousineAddressValue(
          displayText: widget.value.displayLabel,
          canonicalLabel: widget.value.displayLabel,
          lat: widget.value.lat,
          lon: widget.value.lon,
          placeId: widget.value.placeId,
          acceptance: widget.value.hasValidCoordinates
              ? LimousineAddressAcceptance.selected
              : LimousineAddressAcceptance.manualFallback,
        ),
        userConfirmed:
            widget.value.hasValidCoordinates &&
            !widget.value.positionNeedsConfirm,
      );
    }
    _controller.addListener(_onLookupChanged);
    _houseCtrl.addListener(_onManualPartsChanged);
    _additionCtrl.addListener(_onManualPartsChanged);
    _busCtrl.addListener(_onManualPartsChanged);
    _focus.addListener(_scrollWhenFocused);
  }

  @override
  void didUpdateWidget(covariant CustomerProfileAddressEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.setDisplayLanguage(widget.language.name);
    _bindContext();
    if (oldWidget.value.displayLabel != widget.value.displayLabel &&
        widget.value.displayLabel != _controller.textController.text.trim()) {
      _syncing = true;
      _controller.acceptCopy(
        LimousineAddressValue(
          displayText: widget.value.displayLabel,
          canonicalLabel: widget.value.displayLabel,
          lat: widget.value.lat,
          lon: widget.value.lon,
          placeId: widget.value.placeId,
          acceptance: widget.value.hasValidCoordinates
              ? LimousineAddressAcceptance.selected
              : LimousineAddressAcceptance.manualFallback,
        ),
        userConfirmed:
            widget.value.hasValidCoordinates &&
            !widget.value.positionNeedsConfirm,
      );
      _houseCtrl.text = widget.value.houseNumber;
      _additionCtrl.text = widget.value.houseAddition;
      _busCtrl.text = widget.value.bus;
      _syncing = false;
    }
  }

  void _bindContext() {
    _controller.searchContextCountry = () {
      final country = (widget.contextCountry ?? widget.value.country).trim();
      return country.isEmpty ? 'be' : country.toLowerCase();
    };
    _controller.searchContextHint = () {
      final parts = <String>[
        (widget.contextPostalCode ?? widget.value.postalCode).trim(),
        (widget.contextLocality ?? widget.value.locality).trim(),
      ].where((part) => part.isNotEmpty).toList(growable: false);
      return parts.isEmpty ? null : parts.join(' ');
    };
  }

  void _scrollWhenFocused() {
    if (!_focus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        alignment: 0.08,
        curve: Curves.easeOut,
      );
    });
  }

  String _placeTypeOf(
    LimousineAddressValue selected,
    LimousinePlaceSuggestion? candidate,
  ) {
    final fromCandidate = (candidate?.placeType ?? '').trim();
    if (fromCandidate.isNotEmpty) return fromCandidate;
    final id = (selected.placeId ?? '').toLowerCase();
    if (id.startsWith('address.')) return 'address';
    if (id.startsWith('street.')) return 'street';
    return '';
  }

  void _onLookupChanged() {
    if (_syncing) return;
    final selected = _controller.value;
    final text = selected.displayText.trim().isNotEmpty
        ? selected.displayText.trim()
        : _controller.textController.text.trim();
    if (text.isEmpty) {
      widget.onChanged(CustomerStoredAddress.empty);
      return;
    }
    final candidate = _controller.locationCandidate;
    final chosen =
        selected.acceptance == LimousineAddressAcceptance.selected ||
        selected.acceptance == LimousineAddressAcceptance.manualFallback ||
        selected.hasCoordinates ||
        candidate != null;
    if (!chosen) {
      final typed = customerStoredAddressFromLabel(text);
      if (typed.houseNumber.isEmpty && typed.postalCode.isEmpty) {
        return;
      }
    }
    CustomerStoredAddress next;
    if (selected.hasCoordinates || candidate != null) {
      final suggestion = LimousinePlaceSuggestion(
        label: selected.canonicalLabel.trim().isNotEmpty
            ? selected.canonicalLabel
            : text,
        lat: selected.lat ?? candidate?.lat,
        lon: selected.lon ?? candidate?.lon,
        placeId: selected.placeId ?? candidate?.placeId,
        placeType: _placeTypeOf(selected, candidate),
        postcode: candidate?.postcode ?? '',
        locality: candidate?.locality ?? '',
        country: candidate?.country ?? widget.contextCountry ?? '',
      );
      final typed = customerStoredAddressFromLabel(text);
      next = customerStoredAddressFromSuggestion(
        suggestion,
        keepManual: CustomerStoredAddress(
          street: typed.street.isNotEmpty ? typed.street : widget.value.street,
          houseNumber: _houseCtrl.text.trim().isNotEmpty
              ? _houseCtrl.text
              : typed.houseNumber,
          houseAddition: _additionCtrl.text.trim().isNotEmpty
              ? _additionCtrl.text
              : typed.houseAddition,
          bus: _busCtrl.text.trim().isNotEmpty ? _busCtrl.text : typed.bus,
          postalCode: widget.value.postalCode,
          locality: typed.locality.isNotEmpty
              ? typed.locality
              : widget.value.locality,
          country: widget.value.country,
        ),
      );
    } else {
      next = customerStoredAddressApplyManualParts(
        current: customerStoredAddressFromLabel(text),
        houseNumber: _houseCtrl.text,
        houseAddition: _additionCtrl.text,
        bus: _busCtrl.text,
        postalCode: widget.contextPostalCode,
        locality: widget.contextLocality,
        country: widget.contextCountry,
      );
    }
    _syncing = true;
    if (_houseCtrl.text.trim() != next.houseNumber &&
        next.houseNumber.isNotEmpty) {
      _houseCtrl.text = next.houseNumber;
    }
    if (_additionCtrl.text.trim() != next.houseAddition &&
        next.houseAddition.isNotEmpty) {
      _additionCtrl.text = next.houseAddition;
    }
    if (_busCtrl.text.trim() != next.bus && next.bus.isNotEmpty) {
      _busCtrl.text = next.bus;
    }
    _syncing = false;
    widget.onChanged(next);
    setState(() {});
  }

  void _onManualPartsChanged() {
    if (_syncing) return;
    final current = widget.value.isEmpty
        ? customerStoredAddressFromLabel(_controller.textController.text)
        : widget.value;
    final next = customerStoredAddressApplyManualParts(
      current: current,
      houseNumber: _houseCtrl.text,
      houseAddition: _additionCtrl.text,
      bus: _busCtrl.text,
    );
    _syncing = true;
    final label = next.displayLabel;
    if (label.isNotEmpty &&
        _controller.textController.text.trim() != label) {
      _controller.acceptCopy(
        LimousineAddressValue(
          displayText: label,
          canonicalLabel: label,
          lat: next.lat,
          lon: next.lon,
          placeId: next.placeId,
          acceptance: next.hasValidCoordinates
              ? LimousineAddressAcceptance.selected
              : LimousineAddressAcceptance.manualFallback,
        ),
        userConfirmed: next.hasValidCoordinates && !next.positionNeedsConfirm,
      );
    }
    _syncing = false;
    widget.onChanged(next);
  }

  @override
  void dispose() {
    _controller.removeListener(_onLookupChanged);
    _houseCtrl.removeListener(_onManualPartsChanged);
    _additionCtrl.removeListener(_onManualPartsChanged);
    _busCtrl.removeListener(_onManualPartsChanged);
    _focus.removeListener(_scrollWhenFocused);
    _controller.dispose();
    _houseCtrl.dispose();
    _additionCtrl.dispose();
    _busCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = LimousineUxTokens.fromCustomer(widget.palette);
    final needsHouse =
        widget.requireExactHouse && _houseCtrl.text.trim().isEmpty;
    final needsConfirm =
        widget.value.positionNeedsConfirm ||
        (widget.requireExactHouse && !widget.value.hasValidCoordinates);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LimousineAddressField(
          controller: _controller,
          label: _t(
            nl: 'Adres zoeken',
            en: 'Search address',
            fr: 'Rechercher une adresse',
            es: 'Buscar dirección',
          ),
          tokens: tokens,
          language: widget.language,
          showCurrentLocation: false,
          showCanonicalEcho: true,
          isPickupField: widget.requireExactHouse,
          inputKey: ValueKey<String>('customer_profile_${widget.fieldId}_input'),
          focusNode: _focus,
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _miniField(
                key: widget.requireExactHouse
                    ? kCustomerProfileHomeHouseNumberKey
                    : ValueKey<String>('${widget.fieldId}_house'),
                label: _t(
                  nl: 'Huisnummer',
                  en: 'House number',
                  fr: 'Numéro',
                  es: 'Número',
                ),
                controller: _houseCtrl,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _miniField(
                key: widget.requireExactHouse
                    ? kCustomerProfileHomeAdditionKey
                    : ValueKey<String>('${widget.fieldId}_addition'),
                label: _t(
                  nl: 'Toevoeging',
                  en: 'Addition',
                  fr: 'Complément',
                  es: 'Sufijo',
                ),
                controller: _additionCtrl,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _miniField(
                key: widget.requireExactHouse
                    ? kCustomerProfileHomeBusKey
                    : ValueKey<String>('${widget.fieldId}_bus'),
                label: _t(
                  nl: 'Bus',
                  en: 'Box',
                  fr: 'Boîte',
                  es: 'Bus',
                ),
                controller: _busCtrl,
              ),
            ),
          ],
        ),
        if (needsHouse || needsConfirm) ...[
          const SizedBox(height: 8),
          Text(
            needsHouse
                ? _t(
                    nl: 'Vul het huisnummer aan. Een straat alleen is nog geen ophaaladres.',
                    en: 'Add the house number. A street alone is not a pickup address yet.',
                    fr: 'Ajoutez le numéro. Une rue seule n’est pas encore une adresse de prise en charge.',
                    es: 'Añade el número. Una calle sola aún no es una dirección de recogida.',
                  )
                : _t(
                    nl: 'De kaartpositie moet nog worden bevestigd bij de volgende rit.',
                    en: 'The map position still needs to be confirmed on the next ride.',
                    fr: 'La position sur la carte doit encore être confirmée lors de la prochaine course.',
                    es: 'La posición en el mapa aún debe confirmarse en el próximo viaje.',
                  ),
            key: widget.requireExactHouse
                ? kCustomerProfileHomeConfirmHintKey
                : null,
            style: TextStyle(
              color: widget.palette.textMuted,
              fontSize: 12.2,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }

  Widget _miniField({
    required Key key,
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final palette = widget.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: key,
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(color: palette.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: palette.isDark
                ? palette.background.withOpacity(0.86)
                : palette.surface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.gold, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}
