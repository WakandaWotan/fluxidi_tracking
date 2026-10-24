import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_label_language.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

/// Personal or billing address kept on the customer profile.
///
/// Local storage is the source of truth for coordinates and house additions.
/// The public profile API currently drops unknown home-address keys, so a
/// server round must never wipe a locally saved home address.
class CustomerStoredAddress {
  const CustomerStoredAddress({
    this.label = '',
    this.street = '',
    this.houseNumber = '',
    this.houseAddition = '',
    this.bus = '',
    this.postalCode = '',
    this.locality = '',
    this.country = '',
    this.lat,
    this.lon,
    this.placeId = '',
    this.placeType = '',
    this.positionNeedsConfirm = false,
  });

  static const empty = CustomerStoredAddress();

  final String label;
  final String street;
  final String houseNumber;
  final String houseAddition;
  final String bus;
  final String postalCode;
  final String locality;
  final String country;
  final double? lat;
  final double? lon;
  final String placeId;
  final String placeType;
  final bool positionNeedsConfirm;

  bool get isEmpty =>
      label.trim().isEmpty &&
      street.trim().isEmpty &&
      houseNumber.trim().isEmpty &&
      postalCode.trim().isEmpty &&
      locality.trim().isEmpty;

  bool get hasValidCoordinates =>
      lat != null && lon != null && lat!.isFinite && lon!.isFinite;

  bool get isExactHouseResult {
    final type = placeType.trim().toLowerCase();
    final id = placeId.trim().toLowerCase();
    return type == 'address' || id.startsWith('address.');
  }

  String get houseToken {
    final number = houseNumber.trim();
    final addition = houseAddition.trim();
    if (number.isEmpty) return addition;
    return '$number$addition';
  }

  String get displayLabel {
    final composed = composeCustomerStoredAddressLabel(this);
    return composed.isNotEmpty ? composed : label.trim();
  }

  CustomerStoredAddress copyWith({
    String? label,
    String? street,
    String? houseNumber,
    String? houseAddition,
    String? bus,
    String? postalCode,
    String? locality,
    String? country,
    double? lat,
    double? lon,
    String? placeId,
    String? placeType,
    bool? positionNeedsConfirm,
    bool clearCoordinates = false,
  }) {
    return CustomerStoredAddress(
      label: label ?? this.label,
      street: street ?? this.street,
      houseNumber: houseNumber ?? this.houseNumber,
      houseAddition: houseAddition ?? this.houseAddition,
      bus: bus ?? this.bus,
      postalCode: postalCode ?? this.postalCode,
      locality: locality ?? this.locality,
      country: country ?? this.country,
      lat: clearCoordinates ? null : (lat ?? this.lat),
      lon: clearCoordinates ? null : (lon ?? this.lon),
      placeId: placeId ?? this.placeId,
      placeType: placeType ?? this.placeType,
      positionNeedsConfirm: positionNeedsConfirm ?? this.positionNeedsConfirm,
    );
  }

  factory CustomerStoredAddress.fromJson(Map<String, dynamic> json) {
    String read(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return '';
    }

    double? readCoord(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is num && value.isFinite) return value.toDouble();
        final parsed = double.tryParse((value ?? '').toString().trim());
        if (parsed != null && parsed.isFinite) return parsed;
      }
      return null;
    }

    bool readBool(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is bool) return value;
        final text = (value ?? '').toString().trim().toLowerCase();
        if (text == 'true' || text == '1') return true;
        if (text == 'false' || text == '0') return false;
      }
      return false;
    }

    final parsed = customerStoredAddressFromLabel(read(const ['label', 'display', 'display_label']));
    return CustomerStoredAddress(
      label: read(const ['label', 'display', 'display_label']),
      street: read(const ['street']).isNotEmpty
          ? read(const ['street'])
          : parsed.street,
      houseNumber: read(const ['house_number', 'houseNumber']).isNotEmpty
          ? read(const ['house_number', 'houseNumber'])
          : parsed.houseNumber,
      houseAddition: read(const ['house_addition', 'houseAddition']).isNotEmpty
          ? read(const ['house_addition', 'houseAddition'])
          : parsed.houseAddition,
      bus: read(const ['bus', 'box', 'apartment']).isNotEmpty
          ? read(const ['bus', 'box', 'apartment'])
          : parsed.bus,
      postalCode: read(const ['postal_code', 'postalCode', 'postcode']).isNotEmpty
          ? read(const ['postal_code', 'postalCode', 'postcode'])
          : parsed.postalCode,
      locality: read(const ['locality', 'city']).isNotEmpty
          ? read(const ['locality', 'city'])
          : parsed.locality,
      country: read(const ['country', 'country_code', 'countryCode']).toUpperCase(),
      lat: readCoord(const ['lat', 'latitude']),
      lon: readCoord(const ['lon', 'lng', 'longitude']),
      placeId: read(const ['place_id', 'placeId']),
      placeType: read(const ['place_type', 'placeType']),
      positionNeedsConfirm: readBool(const [
        'position_needs_confirm',
        'positionNeedsConfirm',
      ]),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'label': displayLabel,
      'street': street,
      'house_number': houseNumber,
      'houseNumber': houseNumber,
      'house_addition': houseAddition,
      'houseAddition': houseAddition,
      'bus': bus,
      'postal_code': postalCode,
      'postalCode': postalCode,
      'locality': locality,
      'city': locality,
      'country': country,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      'place_id': placeId,
      'placeId': placeId,
      'place_type': placeType,
      'placeType': placeType,
      'position_needs_confirm': positionNeedsConfirm,
      'positionNeedsConfirm': positionNeedsConfirm,
    };
  }
}

final _busPattern = RegExp(
  r'\b(?:bus|bte|box|apt|app|appartement)\s*\.?\s*([0-9A-Za-z]+)\b',
  caseSensitive: false,
);

String customerNormalizeAddressPart(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String customerHouseAdditionToken(String raw) {
  return raw.trim().replaceAll(RegExp(r'[\s./-]'), '').toUpperCase();
}

String? customerParseBusNumber(String raw) {
  final match = _busPattern.firstMatch(raw);
  return match?.group(1)?.trim();
}

String customerCountryDisplayName(String code, [String? language]) {
  final lang = (language ?? currentLanguageCode).trim();
  final official = limousineOfficialAddressPart(code.trim(), lang);
  if (official != null) return official;
  switch (code.trim().toUpperCase()) {
    case 'BE':
      return limousineOfficialAddressPart('België', lang) ?? 'België';
    case 'NL':
      return limousineOfficialAddressPart('Nederland', lang) ?? 'Nederland';
    case 'FR':
      return limousineOfficialAddressPart('Frankrijk', lang) ?? 'Frankrijk';
    case 'DE':
      return limousineOfficialAddressPart('Duitsland', lang) ?? 'Duitsland';
    case 'LU':
      return limousineOfficialAddressPart('Luxemburg', lang) ?? 'Luxemburg';
    default:
      return code.trim();
  }
}

String composeCustomerStoredAddressLabel(
  CustomerStoredAddress address, {
  String? language,
}) {
  final lang = (language ?? currentLanguageCode).trim();
  final streetLine = <String>[
    address.street.trim(),
    address.houseToken,
    if (address.bus.trim().isNotEmpty) 'bus ${address.bus.trim()}',
  ].where((part) => part.isNotEmpty).join(' ');
  final locality = <String>[
    address.postalCode.trim(),
    address.locality.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
  final country = address.country.trim().isEmpty
      ? ''
      : customerCountryDisplayName(address.country, lang);
  final line = <String>[
    if (streetLine.isNotEmpty) streetLine,
    if (locality.isNotEmpty) locality,
    if (country.isNotEmpty) country,
  ].join(', ');
  if (line.isEmpty) {
    final fallback = address.label.trim();
    return fallback.isEmpty
        ? ''
        : limousineLocalizeAddressLabel(fallback, lang);
  }
  return limousineLocalizeAddressLabel(line, lang);
}

CustomerStoredAddress customerStoredAddressFromLabel(String raw) {
  final label = raw.trim();
  if (label.isEmpty) return CustomerStoredAddress.empty;
  final bus = customerParseBusNumber(label) ?? '';
  var working = label;
  if (bus.isNotEmpty) {
    working = working.replaceAll(_busPattern, '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  final parts = limousineParseStreetHouse(working);
  return CustomerStoredAddress(
    label: label,
    street: parts.street,
    houseNumber: parts.number,
    houseAddition: parts.letter,
    bus: bus,
    postalCode: limousineAddressQueryPostcode(working) ?? '',
    locality: limousineAddressQueryLocality(working) ?? '',
    country: (limousineMapboxCountryForQuery(working) ?? '').toUpperCase(),
  );
}

CustomerStoredAddress customerStoredAddressFromSuggestion(
  LimousinePlaceSuggestion suggestion, {
  CustomerStoredAddress? keepManual,
}) {
  final parsed = customerStoredAddressFromLabel(suggestion.label);
  final houseNumber = parsed.houseNumber.isNotEmpty
      ? parsed.houseNumber
      : (keepManual?.houseNumber ?? '');
  final addition = parsed.houseAddition.isNotEmpty
      ? parsed.houseAddition
      : (keepManual?.houseAddition ?? '');
  final bus = (keepManual?.bus ?? '').trim().isNotEmpty
      ? keepManual!.bus.trim()
      : parsed.bus;
  final exact = suggestion.isStreetLevel && houseNumber.isNotEmpty;
  final next = CustomerStoredAddress(
    street: parsed.street.isNotEmpty ? parsed.street : (keepManual?.street ?? ''),
    houseNumber: houseNumber,
    houseAddition: addition,
    bus: bus,
    postalCode: suggestion.postcode.trim().isNotEmpty
        ? suggestion.postcode.trim()
        : (parsed.postalCode.isNotEmpty
              ? parsed.postalCode
              : (keepManual?.postalCode ?? '')),
    locality: customerPreferLocality(
      parsed: parsed.locality,
      suggestion: suggestion.locality,
      keepManual: keepManual?.locality,
    ),
    country: suggestion.country.trim().isNotEmpty
        ? suggestion.country.trim().toUpperCase()
        : (parsed.country.isNotEmpty
              ? parsed.country
              : (keepManual?.country ?? 'BE')),
    lat: suggestion.lat,
    lon: suggestion.lon,
    placeId: (suggestion.placeId ?? '').trim(),
    placeType: suggestion.placeType.trim(),
    positionNeedsConfirm: !exact,
  );
  return next.copyWith(label: composeCustomerStoredAddressLabel(next));
}

CustomerStoredAddress customerStoredAddressApplyManualParts({
  required CustomerStoredAddress current,
  String? street,
  String? houseNumber,
  String? houseAddition,
  String? bus,
  String? postalCode,
  String? locality,
  String? country,
}) {
  final next = current.copyWith(
    street: street ?? current.street,
    houseNumber: houseNumber ?? current.houseNumber,
    houseAddition: houseAddition ?? current.houseAddition,
    bus: bus ?? current.bus,
    postalCode: postalCode ?? current.postalCode,
    locality: locality ?? current.locality,
    country: country ?? current.country,
  );
  final identityChanged = customerStoredAddressIdentityChanged(current, next);
  return next.copyWith(
    label: composeCustomerStoredAddressLabel(next),
    positionNeedsConfirm: identityChanged ? true : next.positionNeedsConfirm,
    clearCoordinates: identityChanged,
    placeId: identityChanged ? '' : next.placeId,
    placeType: identityChanged ? '' : next.placeType,
  );
}

String customerStoredAddressStreetLine(CustomerStoredAddress address) {
  return [
    address.street.trim(),
    address.houseToken,
    if (address.bus.trim().isNotEmpty) 'bus ${address.bus.trim()}',
  ].where((part) => part.isNotEmpty).join(' ');
}

CustomerStoredAddress customerStoredAddressFromBillingFields({
  required String street,
  required String postalCode,
  required String city,
  required String country,
}) {
  final line = [
    street.trim(),
    [
      postalCode.trim(),
      city.trim(),
    ].where((part) => part.isNotEmpty).join(' '),
    country.trim(),
  ].where((part) => part.isNotEmpty).join(', ');
  return customerStoredAddressFromLabel(line);
}

/// Keep a deelgemeente from the typed/saved label when the provider only
/// returns the parent municipality (e.g. Schorisse vs Maarkedal).
String customerPreferLocality({
  required String parsed,
  String suggestion = '',
  String? keepManual,
}) {
  final manual = (keepManual ?? '').trim();
  final fromLabel = parsed.trim();
  final fromProvider = suggestion.trim();
  if (manual.isNotEmpty) return manual;
  if (fromLabel.isNotEmpty) return fromLabel;
  return fromProvider;
}

bool customerStoredAddressIdentityChanged(
  CustomerStoredAddress left,
  CustomerStoredAddress right,
) {
  return customerNormalizeAddressPart(left.street) !=
          customerNormalizeAddressPart(right.street) ||
      customerNormalizeAddressPart(left.houseNumber) !=
          customerNormalizeAddressPart(right.houseNumber) ||
      customerHouseAdditionToken(left.houseAddition) !=
          customerHouseAdditionToken(right.houseAddition) ||
      customerNormalizeAddressPart(left.postalCode) !=
          customerNormalizeAddressPart(right.postalCode) ||
      customerNormalizeAddressPart(left.country) !=
          customerNormalizeAddressPart(right.country);
}
