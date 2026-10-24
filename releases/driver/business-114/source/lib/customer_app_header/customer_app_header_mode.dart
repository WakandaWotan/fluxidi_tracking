/// Display mode for a company's own white-label customer-app header.
///
/// Owned by the header agent. Do not fold tariff or pricing fields into this
/// library. Persistence uses a dedicated authorized settings write that merges
/// only these fields into the existing business profile.
library;

/// How the company's own customer app shows the saved logo and cover.
enum CustomerAppHeaderMode {
  /// Large company logo only. Default for companies without a stored choice.
  logoOnly,

  /// Full saved cover / header image, no extra standalone logo.
  coverOnly,

  /// Full cover with a compact company logo on top of the image.
  coverAndLogo,
}

/// Where the compact logo sits on the cover in [CustomerAppHeaderMode.coverAndLogo].
enum CustomerAppHeaderLogoPosition {
  /// Default. Stays clear of the language and theme chips.
  topLeft,

  /// Opposite corner of the cover. Still inset from the chip row above.
  topRight,
}

/// Wire value stored on the authorized business-profile record.
const String kCustomerAppHeaderModeLogo = 'logo';
const String kCustomerAppHeaderModeCover = 'header_image';
const String kCustomerAppHeaderModeBoth = 'header_and_logo';

const String kCustomerAppHeaderModeField = 'customer_app_header_mode';
const String kCustomerAppHeaderModeFieldCamel = 'customerAppHeaderMode';
const String kCustomerAppHeaderLogoPositionField =
    'customer_app_header_logo_position';
const String kCustomerAppHeaderLogoPositionFieldCamel =
    'customerAppHeaderLogoPosition';
const String kCustomerAppHeaderLogoPositionLeft = 'top_left';
const String kCustomerAppHeaderLogoPositionRight = 'top_right';
const String kCustomerAppHeaderMediaRevisionField =
    'customer_app_header_media_revision';
const String kDriverAppUseCompanyHeaderField =
    'driver_app_use_company_header';
const String kDriverAppUseCompanyHeaderFieldCamel =
    'driverAppUseCompanyHeader';
const String kBusinessAppUseCompanyHeaderField =
    'business_app_use_company_header';
const String kBusinessAppUseCompanyHeaderFieldCamel =
    'businessAppUseCompanyHeader';

/// Missing or unrecognized values stay off. Only an explicit true enables it.
bool parseDriverAppUseCompanyHeader(Object? raw) {
  if (raw == true) return true;
  final value = raw?.toString().trim().toLowerCase() ?? '';
  return value == 'true' || value == '1' || value == 'yes';
}

bool parseBusinessAppUseCompanyHeader(Object? raw) =>
    parseDriverAppUseCompanyHeader(raw);

/// Companies that never saved a choice keep [CustomerAppHeaderMode.logoOnly].
CustomerAppHeaderMode parseCustomerAppHeaderMode(Object? raw) {
  final value = raw?.toString().trim().toLowerCase().replaceAll('-', '_') ?? '';
  switch (value) {
    case kCustomerAppHeaderModeCover:
    case 'cover':
    case 'cover_only':
    case 'header':
    case 'header_only':
    case 'headerimage':
    case 'alleen_headerafbeelding':
      return CustomerAppHeaderMode.coverOnly;
    case kCustomerAppHeaderModeBoth:
    case 'cover_and_logo':
    case 'header+logo':
    case 'header_logo':
    case 'both':
      return CustomerAppHeaderMode.coverAndLogo;
    default:
      return CustomerAppHeaderMode.logoOnly;
  }
}

CustomerAppHeaderLogoPosition parseCustomerAppHeaderLogoPosition(Object? raw) {
  final value = raw?.toString().trim().toLowerCase().replaceAll('-', '_') ?? '';
  switch (value) {
    case kCustomerAppHeaderLogoPositionRight:
    case 'right':
    case 'topright':
    case 'rechtsboven':
      return CustomerAppHeaderLogoPosition.topRight;
    default:
      return CustomerAppHeaderLogoPosition.topLeft;
  }
}

String customerAppHeaderLogoPositionWire(
  CustomerAppHeaderLogoPosition position,
) {
  switch (position) {
    case CustomerAppHeaderLogoPosition.topRight:
      return kCustomerAppHeaderLogoPositionRight;
    case CustomerAppHeaderLogoPosition.topLeft:
      return kCustomerAppHeaderLogoPositionLeft;
  }
}

String customerAppHeaderModeWire(CustomerAppHeaderMode mode) {
  switch (mode) {
    case CustomerAppHeaderMode.logoOnly:
      return kCustomerAppHeaderModeLogo;
    case CustomerAppHeaderMode.coverOnly:
      return kCustomerAppHeaderModeCover;
    case CustomerAppHeaderMode.coverAndLogo:
      return kCustomerAppHeaderModeBoth;
  }
}

/// Cover-based choices fall back to the logo when the cover is missing or
/// unusable. A missing logo still keeps the requested cover when it is usable.
CustomerAppHeaderMode effectiveCustomerAppHeaderMode({
  required CustomerAppHeaderMode requested,
  required bool hasLogo,
  required bool hasCover,
}) {
  switch (requested) {
    case CustomerAppHeaderMode.coverOnly:
      return hasCover ? CustomerAppHeaderMode.coverOnly : CustomerAppHeaderMode.logoOnly;
    case CustomerAppHeaderMode.coverAndLogo:
      if (hasCover && hasLogo) return CustomerAppHeaderMode.coverAndLogo;
      if (hasCover) return CustomerAppHeaderMode.coverOnly;
      return CustomerAppHeaderMode.logoOnly;
    case CustomerAppHeaderMode.logoOnly:
      return CustomerAppHeaderMode.logoOnly;
  }
}
