/**
 * Shared Fluxidi event-market list for website, Worker and app.
 *
 * Event search is independent of taxi-company registration, billing and
 * phone countries. Those lists do not limit the catalog.
 *
 * Selectable countries are the Ticketmaster-proven set plus FR and PT
 * (open research). Eighteen countries is not full European coverage.
 *
 * The Worker does not allow-list countries: any ISO code may be queried.
 */

export const FLUXIDI_EVENT_MARKETS_SOURCE =
  "event-catalog independent of company/billing/phone; TM-proven + FR/PT research; not full Europe";

export const FLUXIDI_EVENT_MARKETS = [
  { key: "be", country: "BE", selectable: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "nl", country: "NL", selectable: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "fr", country: "FR", selectable: true, sourceSupported: false, proven: false, coverage: "unconfirmed", extraSource: "openagenda", extraKey: "OPENAGENDA_API_KEY" },
  { key: "uk", country: "GB", selectable: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "de", country: "DE", selectable: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "lu", country: "LU", selectable: true, sourceSupported: true, proven: true, coverage: "thin" },
  { key: "es", country: "ES", selectable: true, sourceSupported: true, proven: true, coverage: "category" },
  { key: "pt", country: "PT", selectable: true, sourceSupported: false, proven: false, coverage: "unconfirmed" },
  { key: "it", country: "IT", selectable: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "at", country: "AT", selectable: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "ie", country: "IE", selectable: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "ch", country: "CH", selectable: true, sourceSupported: true, proven: true, coverage: "general" },
  { key: "dk", country: "DK", selectable: true, sourceSupported: true, proven: true, coverage: "category" },
  { key: "se", country: "SE", selectable: true, sourceSupported: true, proven: true, coverage: "category" },
  { key: "no", country: "NO", selectable: true, sourceSupported: true, proven: true, coverage: "category" },
  { key: "fi", country: "FI", selectable: true, sourceSupported: true, proven: true, coverage: "category" },
  { key: "pl", country: "PL", selectable: true, sourceSupported: true, proven: true, coverage: "category" },
  { key: "cz", country: "CZ", selectable: true, sourceSupported: true, proven: true, coverage: "category" },
];

export const FLUXIDI_EVENT_MARKET_KEYS = FLUXIDI_EVENT_MARKETS
  .filter((row) => row.selectable)
  .map((row) => row.key);

export const FLUXIDI_EVENT_COUNTRIES = FLUXIDI_EVENT_MARKETS
  .filter((row) => row.selectable)
  .map((row) => row.country);

export const FLUXIDI_LAUNCH_EVENT_COUNTRIES = FLUXIDI_EVENT_COUNTRIES.slice();

export const FLUXIDI_TM_PROVEN_EXTRA_COUNTRIES = [];

export function selectableEventMarketKeys() {
  return FLUXIDI_EVENT_MARKET_KEYS.slice();
}
