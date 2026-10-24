import 'package:fluxidi_tracking/company/company_public_booking_link.dart';

const marioCompanyId = 'cmp_taxi-mario_4b6d297325';
const fluxidiCompanyId = 'fluxidi_fluxidi_ddmh9g';

Map<String, dynamic> bookingIdentity({
  String company = marioCompanyId,
  String slug = 'TAXI-MARIO',
}) => {
  'ok': true,
  'company_id': company,
  'tenant_id': company,
  'public_company_slug': slug,
  'company': {
    'company_id': company,
    'tenant_id': company,
    'publicCompanySlug': slug,
  },
};

Map<String, dynamic> bookingContext({
  String company = marioCompanyId,
  String slug = 'taxi-mario',
  String name = 'Taxi Mario',
}) => {
  'ok': true,
  'slug': slug,
  'company': {
    'company_id': company,
    'tenant_id': company,
    'company_name': name,
  },
  'profile': {
    'company_id': company,
    'tenant_id': company,
    'is_active': true,
    'bookable': true,
    'profile_enabled': true,
    'account_state': 'active',
  },
};

Future<CompanyPublicBookingLink> testBookingLink({
  String company = marioCompanyId,
  String slug = 'taxi-mario',
  String name = 'Taxi Mario',
}) => resolveCompanyPublicBookingLink(
  expectedCompanyId: company,
  profileLoader: () async => bookingIdentity(company: company, slug: slug),
  contextLoader: (value) async =>
      bookingContext(company: company, slug: value, name: name),
);
