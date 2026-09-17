/**
 * Shared Fluxidi event-market list for website, Worker and app.
 *
 * Fluxidi-offered company countries:
 *   lib/business_settings_page.dart → `_kBusinessCountryCodes`
 *   BE, NL, LU, FR, DE, ES, PT, GB
 *
 * Extra European customer countries already in Fluxidi billing/phone maps:
 *   lib/main_parts/ride_receipt_body_state.dart (IT, AT, IE, CH)
 *
 * Ticketmaster can also return DK, SE, NO, FI, PL, CZ. Those stay documented
 * as source-supported extras and are not selectable until Fluxidi offers them.
 *
 * Selectable ≠ proven coverage. The Worker does not allow-list countries:
 * any ISO code may be queried. UI lists come from selectableKeys().
 */

export const FLUXIDI_EVENT_MARKETS_SOURCE =
  "company:_kBusinessCountryCodes + billing/phone Europe IT/AT/IE/CH";

export const FLUXIDI_EVENT_MARKETS = [
  { key: "be", country: "BE", selectable: true, offered: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "nl", country: "NL", selectable: true, offered: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "fr", country: "FR", selectable: true, offered: true, sourceSupported: false, proven: false, coverage: "unconfirmed", extraSource: "openagenda", extraKey: "OPENAGENDA_API_KEY" },
  { key: "uk", country: "GB", selectable: true, offered: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "de", country: "DE", selectable: true, offered: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "lu", country: "LU", selectable: true, offered: true, sourceSupported: true, proven: true, coverage: "thin" },
  { key: "es", country: "ES", selectable: true, offered: true, sourceSupported: true, proven: true, coverage: "category" },
  { key: "pt", country: "PT", selectable: true, offered: true, sourceSupported: false, proven: false, coverage: "unconfirmed" },
  { key: "it", country: "IT", selectable: true, offered: false, sourceSupported: true, proven: true, coverage: "general" },
  { key: "at", country: "AT", selectable: true, offered: false, sourceSupported: true, proven: true, coverage: "general" },
  { key: "ie", country: "IE", selectable: true, offered: false, sourceSupported: true, proven: true, coverage: "general" },
  { key: "ch", country: "CH", selectable: true, offered: false, sourceSupported: true, proven: true, coverage: "general" },
  { key: "dk", country: "DK", selectable: false, offered: false, sourceSupported: true, proven: true, coverage: "category" },
  { key: "se", country: "SE", selectable: false, offered: false, sourceSupported: true, proven: true, coverage: "category" },
  { key: "no", country: "NO", selectable: false, offered: false, sourceSupported: true, proven: true, coverage: "category" },
  { key: "fi", country: "FI", selectable: false, offered: false, sourceSupported: true, proven: true, coverage: "category" },
  { key: "pl", country: "PL", selectable: false, offered: false, sourceSupported: true, proven: true, coverage: "category" },
  { key: "cz", country: "CZ", selectable: false, offered: false, sourceSupported: true, proven: true, coverage: "category" },
];

export const FLUXIDI_EVENT_MARKET_KEYS = FLUXIDI_EVENT_MARKETS
  .filter((row) => row.selectable)
  .map((row) => row.key);

export const FLUXIDI_EVENT_COUNTRIES = FLUXIDI_EVENT_MARKETS
  .filter((row) => row.selectable)
  .map((row) => row.country);

export const FLUXIDI_LAUNCH_EVENT_COUNTRIES = FLUXIDI_EVENT_COUNTRIES.slice();

export const FLUXIDI_TM_PROVEN_EXTRA_COUNTRIES = FLUXIDI_EVENT_MARKETS
  .filter((row) => !row.selectable && row.sourceSupported)
  .map((row) => row.country);

export function selectableEventMarketKeys() {
  return FLUXIDI_EVENT_MARKET_KEYS.slice();
}
